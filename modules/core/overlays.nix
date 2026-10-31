{ inputs, lib, ... }:
let
  # `packages.default`, never the input's `overlays.default`: that overlay
  # rebuilds via callPackage against OUR nixpkgs, so no store hash matches the
  # input's binary cache.
  fromInputs = lib.flip lib.genAttrs (
    name: final: _prev: {
      ${name} = inputs.${name}.packages.${final.stdenv.hostPlatform.system}.default;
    }
  );
in
{
  flake.overlays =
    fromInputs [
      "lys-shell"
      "lys-wm"
      "lys-login"
      "phpantom_lsp"
      "shell-lsp"
      "claude-code"
      "xilo"
      "adaptive-power-manager"
    ]
    // {
      # Lazy: forced only when something consumes pkgs.nixgl, the standalone-HM
      # Intel fallback in pkgs/gl.nix; NixOS hosts and NVIDIA machines use system
      # GL and never touch it.
      # nixGL.nix is called directly, not via default.nix, so its `pcre` argument
      # can be replaced: nixpkgs removed pcre, and nixGL's script checkPhase
      # still runs `pcregrep`. pcre2grep is its drop-in successor.
      nixgl =
        final: _prev:
        let
          inherit (final.stdenv.hostPlatform) isx86_64;
        in
        {
          nixgl = final.callPackage "${inputs.nixgl}/nixGL.nix" (
            {
              enable32bits = isx86_64;
              pcre = final.runCommand "pcregrep-pcre2" { } ''
                mkdir -p $out/bin
                ln -s ${final.lib.getExe' final.pcre2 "pcre2grep"} $out/bin/pcregrep
              '';
            }
            // final.lib.optionalAttrs (!isx86_64) { intel-media-driver = null; }
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
        yayamlls =
          final.runCommand "yayamlls"
            {
              meta = {
                mainProgram = "yayamlls";
                platforms = [ "x86_64-linux" ];
              };
            }
            ''
              install -Dm555 ${inputs.yayamlls}/yayamlls $out/bin/yayamlls
            '';
      };

      # tela-circle-icon-theme 2026-07-07 ships three symlinks to icons
      # that do not exist in the release (xsi-addon-symbolic.svg,
      # org.xfce.appfinder.svg); the stdenv noBrokenSymlinks check rejects
      # the whole package for it. Upstream declined to skip the check for
      # the square sibling (nixpkgs#382288), so prune the dangling links
      # here. Deletable once the theme or nixpkgs adapts.
      tela-icon-fix = _final: prev: {
        tela-circle-icon-theme = prev.tela-circle-icon-theme.overrideAttrs (old: {
          preFixup = (old.preFixup or "") + ''
            find $out/share/icons -xtype l -delete
          '';
        });
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

      mago-runpath = final: prev: {
        mago =
          final.runCommand prev.mago.name
            {
              nativeBuildInputs = [ final.patchelf ];
              inherit (prev.mago) meta;
            }
            ''
              cp -r ${prev.mago} $out
              chmod -R u+w $out
              patchelf --set-rpath "$(patchelf --print-rpath $out/bin/mago | tr ':' '\n' | grep -v '/rustlib/' | paste -sd: -)" $out/bin/mago
            '';
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
