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

    phpantom_lsp = final: _prev: {
      phpantom_lsp = inputs.phpantom_lsp.packages.${final.stdenv.hostPlatform.system}.default;
    };

    xilo = final: _prev: {
      xilo = inputs.xilo.packages.${final.stdenv.hostPlatform.system}.default;
    };

    headroom =
      final: _prev:
      let
        py = final.python313Packages;
      in
      {
        headroom = py.buildPythonApplication rec {
          pname = "headroom-ai";
          version = "0.37.0";
          format = "wheel";

          src = final.fetchurl {
            url = "https://files.pythonhosted.org/packages/72/b8/16878cf4fe6fc390a0d22025b671468619db690ff14c1b103ace4b5e35f9/headroom_ai-${version}-cp310-abi3-manylinux_2_28_x86_64.whl";
            hash = "sha256-Lvxc32gaEMX8eionGkcRecQJB0U3BF9oKxDk1ySXb0Y=";
          };

          nativeBuildInputs = [ final.autoPatchelfHook ];
          buildInputs = [ (final.lib.getLib final.stdenv.cc.cc) ];

          propagatedBuildInputs = with py; [
            ast-grep-cli
            click
            litellm
            opentelemetry-api
            pydantic
            pyyaml
            rich
            tiktoken
            tomlkit

            fastapi
            h2
            httpx
            magika
            mcp
            onnxruntime
            openai
            orjson
            sqlite-vec
            transformers
            uvicorn
            watchdog
            websockets
            zstandard
          ];

          postFixup = ''
            wrapProgram $out/bin/headroom \
              --set HEADROOM_BEACON off \
              --set DO_NOT_TRACK 1 \
              --set HEADROOM_TELEMETRY off \
              --set HEADROOM_TELEMETRY_WARN off \
              --set HEADROOM_UPDATE_CHECK off
          '';

          pythonImportsCheck = [ "headroom" ];

          meta = {
            description = "Context compression proxy for LLM agents";
            homepage = "https://github.com/headroomlabs-ai/headroom";
            license = final.lib.licenses.asl20;
            mainProgram = "headroom";
            platforms = [ "x86_64-linux" ];
          };
        };
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

    stubbe-packages = final: prev: {
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

      # `hm upgrade` only rewrites `github:owner/repo/tag` flake inputs, so this
      # tarball pin has to be bumped by hand.
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
