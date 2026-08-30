# nixpkgs overlays: third-party flake packages surfaced into `pkgs`, upstream
# fixes we carry, and the handful of packages this repo builds itself.
#
# Every overlay registered under `flake.overlays` is applied to BOTH targets:
# the standalone-HM pkgs (modules/core/flake.nix) and NixOS's `nixpkgs.overlays`
# (modules/nix.nix), so a `pkgs.<x>` reference resolves identically on either.
{ inputs, ... }:
let
  # Auto-detect the NVIDIA driver version from /proc, for both the proprietary
  # and the Open kernel modules. Requires --impure (the flake already runs
  # that way) so the /proc read succeeds.
  nvidiaVersion =
    let
      versionPath = /. + "/proc/driver/nvidia/version";
    in
    if builtins.pathExists versionPath then
      let
        match = builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" (
          builtins.readFile versionPath
        );
      in
      if match != null then builtins.head match else null
    else
      null;
in
{
  flake.overlays = {
    # nixGL, instantiated with the detected NVIDIA version.
    nixgl =
      final: _prev:
      let
        isIntelX86 = final.stdenv.hostPlatform.system == "x86_64-linux";
      in
      {
        nixgl = import "${inputs.nixgl}/default.nix" (
          {
            pkgs = final;
            enable32bits = isIntelX86;
            enableIntelX86Extensions = isIntelX86;
          }
          // final.lib.optionalAttrs (nvidiaVersion != null) { inherit nvidiaVersion; }
        );
      };

    # cship ships no flake (`flake = false`); build it from its Cargo manifest.
    cship =
      final: _prev:
      let
        src = inputs.cship;
        cargoMeta = (fromTOML (builtins.readFile "${src}/Cargo.toml")).package;
      in
      {
        cship = final.rustPlatform.buildRustPackage {
          pname = cargoMeta.name;
          inherit (cargoMeta) version;
          inherit src;
          cargoLock.lockFile = src + "/Cargo.lock";
          doCheck = false;
        };
      };

    # wayle ships its own flake. Use its prebuilt `packages.default` (from the
    # nix.stubbe.dev binary cache) rather than its `overlays.default`: that
    # overlay rebuilds via `prev.callPackage` against OUR nixpkgs, whose
    # store-path hashes never match the CI-built cache (built against wayle's
    # own nixpkgs), so everything would rebuild from source. Requires
    # wayle.inputs.nixpkgs NOT following ours — see flake.nix.
    wayle = _final: prev: {
      wayle = inputs.wayle.packages.${prev.stdenv.hostPlatform.system}.default;
    };

    # phpantom_lsp / xilo: flake packages surfaced so both targets see them
    # through the shared overlay set.
    phpantom_lsp = final: _prev: {
      phpantom_lsp = inputs.phpantom_lsp.packages.${final.stdenv.hostPlatform.system}.default;
    };

    xilo = final: _prev: {
      xilo = inputs.xilo.packages.${final.stdenv.hostPlatform.system}.default;
    };

    # pcmanfm's wrapper injects only dconf into GIO_EXTRA_MODULES, so its glib
    # finds no gvfs client module and every dav:// / smb:// / mtp:// URI fails
    # with "Operation not supported". wrapGAppsHook3 appends the module dir of
    # any buildInput that ships one, so listing gvfs bakes the path into the
    # binary whatever launches it (rofi, .desktop, shell). On NixOS
    # services.gvfs already exports the variable session-wide; the baked prefix
    # is the same directory.
    pcmanfm-gvfs = _final: prev: {
      pcmanfm = prev.pcmanfm.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ prev.gvfs ];
      });
    };

    # Assorted Python 3.14 / new-toolchain fallout in nixpkgs. Each override is
    # deletable once nixpkgs or upstream adapts.
    python-fixes = _final: prev: {
      # catppuccin-gtk 1.0.3's build script passes type=bool alongside
      # argparse.BooleanOptionalAction, which Python 3.14 rejects (deprecated
      # in 3.12, removed in 3.14). Strip the kwarg; the action never used it.
      catppuccin-gtk = prev.catppuccin-gtk.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          sed -i '/type=bool,/d' sources/build/args.py
        '';
      });

      pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
        (pyfinal: pyprev: {
          # click-threading's pytest setup collects docs/conf.py, which imports
          # pkg_resources — removed from setuptools 82.
          click-threading = pyprev.click-threading.overridePythonAttrs (_old: {
            disabledTestPaths = [ "docs/conf.py" ];
          });

          # matplotlib 3.11 removed matplotlib.style.core, which catppuccin's
          # style registration still imports on plain `import catppuccin`, so
          # the package's own import check explodes whenever matplotlib is
          # visible. Drop the matplotlib extra from the check env — runtime
          # users like catppuccin-gtk never install it.
          catppuccin = pyprev.catppuccin.overridePythonAttrs (_old: {
            nativeCheckInputs = [
              pyfinal.pytestCheckHook
              pyfinal.pygments
              pyfinal.rich
            ];
            disabledTestPaths = [ "tests/test_matplotlib.py" ];
          });
        })
      ];
    };

    # Packages this repo builds itself.
    stubbe-packages = final: prev: {
      # nixpkgs ships `catppuccin-plymouth` hardcoded to the macchiato flavour.
      # Upstream has all four — swap sourceRoot + install paths for the mocha
      # variant, matching the Kvantum/GTK Catppuccin Mocha set. The sed patches
      # ImageDir so plymouth finds its assets at the final share/ path.
      catppuccin-mocha-plymouth = prev.catppuccin-plymouth.overrideAttrs (_: {
        pname = "catppuccin-mocha-plymouth";
        sourceRoot = "source/themes/catppuccin-mocha";
        installPhase = ''
          runHook preInstall
          sed -i 's:\(^ImageDir=\)/usr:\1'"$out"':' catppuccin-mocha.plymouth
          mkdir -p $out/share/plymouth/themes/catppuccin-mocha
          cp * $out/share/plymouth/themes/catppuccin-mocha
          runHook postInstall
        '';
      });

      # lazy-tmux: tmux session snapshot/restore with scrollback and
      # per-program integrations (a `claude` pane comes back as
      # `claude --resume <id>`). Not in nixpkgs and upstream ships no flake, so
      # pin the release tarball — a statically linked Go binary, nothing to
      # compile. Bumping = new version + that release's sha256 from its
      # checksums.txt; `hm upgrade`'s bump_release_pins only rewrites
      # `github:owner/repo/tag` flake inputs, so this pin is manual.
      lazy-tmux = final.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "lazy-tmux";
        version = "0.2.1";

        src = final.fetchurl {
          url = "https://github.com/alchemmist/lazy-tmux/releases/download/v${finalAttrs.version}/lazy-tmux_linux_amd64.tar.gz";
          sha256 = "ec3d100fd5d297f2f91660977692c24f238896ae265999b32aede8fd1e91c2fa";
        };

        # Tarball has no top-level directory (bin, LICENSE, README side by side).
        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          install -Dm755 lazy-tmux $out/bin/lazy-tmux
          runHook postInstall
        '';

        meta = {
          description = "Lazy tmux session saver and restorer";
          homepage = "https://lazy-tmux.xyz";
          license = final.lib.licenses.mit;
          mainProgram = "lazy-tmux";
          platforms = [ "x86_64-linux" ];
        };
      });
    };
  };
}
