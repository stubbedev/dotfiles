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

    gddy =
      final: _prev:
      let
        src = inputs.gddy;
        cargoMeta = (fromTOML (builtins.readFile "${src}/rust/Cargo.toml")).package;
      in
      {
        gddy = final.rustPlatform.buildRustPackage {
          pname = "gddy";
          inherit (cargoMeta) version;
          inherit src;
          sourceRoot = "source/rust";
          cargoLock.lockFile = src + "/rust/Cargo.lock";
          cargoBuildFlags = [
            "--bin"
            "gddy"
          ];
          doCheck = false;
          meta = {
            description = "Agent-first CLI for the GoDaddy developer platform";
            homepage = "https://github.com/godaddy/cli";
            license = final.lib.licenses.mit;
            mainProgram = "gddy";
            platforms = final.lib.platforms.unix;
          };
        };
      };

    # `packages.default`, never its `overlays.default`: that overlay rebuilds via
    # callPackage against OUR nixpkgs, so no store hash matches the CI cache.
    wayle = _final: prev: {
      wayle = inputs.wayle.packages.${prev.stdenv.hostPlatform.system}.default;
    };

    phpantom_lsp = final: _prev: {
      phpantom_lsp = inputs.phpantom_lsp.packages.${final.stdenv.hostPlatform.system}.default;
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
