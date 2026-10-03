{ inputs, ... }:
let
  # Lazy and guarded: forced only when something consumes pkgs.nixgl (the
  # standalone-HM NVIDIA path; NixOS hosts use system GL and never touch it).
  # tryEval keeps pure evals - hm switch no longer passes --impure - from dying
  # on the absolute-path access: they fall back to generic nixgl.
  nvidiaVersion =
    let
      probed = builtins.tryEval (
        let
          versionPath = /. + "/proc/driver/nvidia/version";
        in
        if builtins.pathExists versionPath then
          builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" (builtins.readFile versionPath)
        else
          null
      );
    in
    if probed.success && probed.value != null then builtins.head probed.value else null;
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
        nodejs-slim = prev.nodejs-slim_24;
      };
    };

    # Prebuilt release binary. The version lives in the `yayamlls` input URL
    # and is pinned by flake.lock like every other input; no hashes or
    # versions are written down here. (It used to scrape the releases atom at
    # eval time, which forced --impure on every rebuild.)
    yayamlls = final: _prev: {
      yayamlls = final.runCommand "yayamlls" { meta.mainProgram = "yayamlls"; } ''
        install -Dm555 ${inputs.yayamlls}/yayamlls $out/bin/yayamlls
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
