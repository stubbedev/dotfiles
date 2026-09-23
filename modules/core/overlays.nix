{ inputs, ... }:
let
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

    # `packages.default`, never its `overlays.default`: that overlay rebuilds via
    # callPackage against OUR nixpkgs, so no store hash matches the CI cache.
    wayle = _final: prev: {
      wayle = inputs.wayle.packages.${prev.stdenv.hostPlatform.system}.default;
    };

    vue-language-server-node = _final: prev: {
      vue-language-server = prev.vue-language-server.override {
        nodejs-slim_latest = prev.nodejs-slim_24;
      };
    };

    # Go YAML language server, replacing node's yaml-language-server: consumed
    # as the upstream release binary -- the same prebuilt pattern as wayle and
    # claude-code. The latest tag is scraped at eval time from the releases
    # atom feed, and the asset download rides the github.com web tier, so
    # neither touches the api.github.com quota the github-token in secrets
    # exists for (that one serves `nix flake update` daemon-side, where nix.conf
    # access-tokens apply; the evaluator cannot authenticate: builtins.fetchurl
    # has no headers support and query-param tokens are long rejected). This
    # only works because every switch and check runs --impure (see README); the
    # fetcher cache pins a tag for an hour. Building from source instead is
    # what forces a vendorHash: go.sum carries no hashes nix can use. Delete
    # once nixpkgs packages it.
    yayamlls =
      final: _prev:
      let
        feed = builtins.readFile (
          builtins.fetchurl {
            url = "https://github.com/home-operations/yayamlls/releases.atom";
            name = "releases.xml";
          }
        );
        # splitString "<title>" yields [ prelude, feedTitle, tag0, tag1, ... ];
        # entries are newest-first, so tag0 is the latest release.
        tag = final.lib.head (
          final.lib.splitString "</title>" (
            final.lib.head (final.lib.tail (final.lib.tail (final.lib.splitString "<title>" feed)))
          )
        );
        assetArch =
          {
            x86_64-linux = "amd64";
            aarch64-linux = "arm64";
          }
          .${final.stdenv.hostPlatform.system}
            or (throw "yayamlls: no release asset for ${final.stdenv.hostPlatform.system}");
        bin = builtins.fetchTarball {
          url = "https://github.com/home-operations/yayamlls/releases/download/${tag}/yayamlls_${tag}_linux_${assetArch}.tar.gz";
        };
      in
      {
        yayamlls = final.runCommand "yayamlls-${tag}" { meta.mainProgram = "yayamlls"; } ''
          install -Dm555 ${bin}/yayamlls $out/bin/yayamlls
        '';
      };

    phpantom_lsp = final: _prev: {
      phpantom_lsp = inputs.phpantom_lsp.packages.${final.stdenv.hostPlatform.system}.default;
    };

    # packages.default, not overlays.default: the overlay callPackages against
    # OUR nixpkgs, so the derivation differs from the cachix cache.
    claude-code = final: _prev: {
      claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
    };

    xilo = final: _prev: {
      xilo = inputs.xilo.packages.${final.stdenv.hostPlatform.system}.default;
    };

    # pcmanfm's wrapper injects only dconf into GIO_EXTRA_MODULES, so without
    # gvfs listed here every dav:// / smb:// / mtp:// URI fails with
    # "Operation not supported".
    pcmanfm-gvfs = _final: prev: {
      pcmanfm = prev.pcmanfm.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ prev.gvfs ];
      });
    };

    # Assorted Python 3.14 / new-toolchain fallout in nixpkgs. Each override is
    # deletable once nixpkgs or upstream adapts.
    python-fixes = _final: prev: {
      catppuccin-gtk = prev.catppuccin-gtk.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          sed -i '/type=bool,/d' sources/build/args.py
        '';
      });

      pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
        (pyfinal: pyprev: {
          click-threading = pyprev.click-threading.overridePythonAttrs (_old: {
            disabledTestPaths = [ "docs/conf.py" ];
          });

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

    stubbe-packages = _final: prev: {
      # nixpkgs hardcodes catppuccin-plymouth to the macchiato flavour; upstream
      # ships all four.
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
    };
  };
}
