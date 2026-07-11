{ inputs, ... }:
let
  # Auto-detect NVIDIA driver version from /proc. Works with both
  # proprietary and Open kernel modules. Requires --impure (the flake
  # already runs that way) so /proc reads succeed.
  nvidiaVersion =
    let
      nvidiaVersionPath = /. + "/proc/driver/nvidia/version";
    in
    if builtins.pathExists nvidiaVersionPath then
      let
        data = builtins.readFile nvidiaVersionPath;
        versionMatch = builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" data;
      in
      if versionMatch != null then builtins.head versionMatch else null
    else
      null;

  # Custom nixGL overlay with NVIDIA version detection
  nixglOverlay =
    final: _prev:
    let
      isIntelX86Platform = final.stdenv.hostPlatform.system == "x86_64-linux";
      nixglArgs = {
        pkgs = final;
        enable32bits = isIntelX86Platform;
        enableIntelX86Extensions = isIntelX86Platform;
      }
      // (if nvidiaVersion != null then { inherit nvidiaVersion; } else { });
    in
    {
      nixgl = import "${inputs.nixgl}/default.nix" nixglArgs;
    };

  cshipOverlay =
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

  # phpantom_lsp ships its own flake; surface packages.default as
  # pkgs.phpantom_lsp so both NixOS (nix-settings.nix) and home-manager
  # (home-manager/pkgs.nix) see it through the shared overlay set.
  phpantomLspOverlay = final: _prev: {
    phpantom_lsp = inputs.phpantom_lsp.packages.${final.stdenv.hostPlatform.system}.default;
  };

  # Assorted Python 3.14 / new-toolchain fallout in nixpkgs python packages.
  # Each override is deletable once nixpkgs/upstream adapts.
  pythonFixesOverlay = _final: prev: {
    # catppuccin-gtk 1.0.3's build script passes type=bool alongside
    # argparse.BooleanOptionalAction, which Python 3.14 rejects (the combo
    # was deprecated in 3.12 and removed in 3.14). Strip the kwarg; the
    # action never used it.
    catppuccin-gtk = prev.catppuccin-gtk.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        sed -i '/type=bool,/d' sources/build/args.py
      '';
    });

    pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
      (pyfinal: pyprev: {
        # click-threading's pytest setup collects docs/conf.py, which imports
        # pkg_resources — removed from setuptools 82. Skip the docs dir.
        click-threading = pyprev.click-threading.overridePythonAttrs (_old: {
          disabledTestPaths = [ "docs/conf.py" ];
        });

        # matplotlib 3.11 removed matplotlib.style.core, which catppuccin's
        # style registration still imports on plain `import catppuccin`, so the
        # package's own import check explodes whenever matplotlib is visible.
        # Drop the matplotlib extra from the check env (runtime users like
        # catppuccin-gtk never install it).
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

in
{
  flake.overlays = {
    nixgl = nixglOverlay;
    cship = cshipOverlay;
    # wayle ships its own flake. Use its prebuilt package (from the
    # nix.stubbe.dev/wayle binary cache) rather than overlays.default:
    # that overlay rebuilds via `prev.callPackage` against OUR nixpkgs, whose
    # store-path hashes never match the CI-built cache (built against wayle's
    # own nixpkgs), so everything rebuilds from source. packages.default is the
    # same whole-workspace derivation (wayle + wayle-settings + desktop/icons).
    # Requires wayle.inputs.nixpkgs NOT following ours (see flake.nix).
    wayle = _final: prev: { wayle = inputs.wayle.packages.${prev.system}.default; };
    phpantom_lsp = phpantomLspOverlay;
    python-fixes = pythonFixesOverlay;
    zsh-patina = final: _prev: {
      zsh-patina = inputs.zsh-patina.packages.${final.stdenv.hostPlatform.system}.default;
    };
  };
}
