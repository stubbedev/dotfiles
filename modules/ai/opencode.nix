_: {
  flake.modules.homeManager.opencode =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.opencode (
      let
        # Each opencode LSP built-in looks its binary up on PATH first and only
        # then falls back to downloading one, so a PATH beats a config table:
        # the built-ins keep their own root-marker and spawn logic, which an
        # explicit `command` override would replace.
        lspPkgs = with pkgs; [
          nixd
          gopls
          rust-analyzer
          lua-language-server
          bash-language-server
          yaml-language-server
          svelte-language-server
          vue-language-server
          ty
        ];

        opencode = pkgs.symlinkJoin {
          name = "opencode-with-lsp";
          paths = [ pkgs.opencode ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/opencode \
              --suffix PATH : ${lib.makeBinPath lspPkgs} \
              --set-default OPENCODE_DISABLE_LSP_DOWNLOAD true \
              --set-default OPENCODE_EXPERIMENTAL_LSP_TY true \
              --set-default OPENCODE_EXPERIMENTAL_LSP_TOOL true
          '';
        };
      in
      {
        home.packages = [ opencode ];

        # opencode merges config.json, opencode.json, then opencode.jsonc, so the
        # .jsonc wins -- and opencode writes an empty stub there itself.
        xdg.configFile."opencode/opencode.jsonc" = {
          force = true;
          source = (pkgs.formats.json { }).generate "opencode.jsonc" {
            "$schema" = "https://opencode.ai/config.json";

            mcp = config.stubbe.mcp.clients.opencode;

            lsp = {
              phpantom = {
                command = [ (lib.getExe' pkgs.phpantom_lsp "phpantom_lsp") ];
                extensions = [ ".php" ];
              };
              # opencode starts EVERY server whose extensions match, not just
              # the first, so the built-in would run a second PHP server.
              "php intelephense".disabled = true;

              # The built-in wants docker-langserver, the node server this
              # config dropped for Docker's Go binary. Reaches *.dockerfile
              # only: servers are keyed on `path.parse(f).ext || f`, which an
              # extensionless Dockerfile can never match.
              dockerfile.command = [
                (lib.getExe' pkgs.docker-language-server "docker-language-server")
                "start"
                "--stdio"
              ];
            };
          };
        };

        xdg.configFile."opencode/plugins/lsp-warnings.js".source =
          ../../src/opencode/plugins/lsp-warnings.js;
        xdg.configFile."opencode/plugins/no-aliases.js".source =
          ../../src/opencode/plugins/no-aliases.js;

        stubbe.setup.opencode.script = ''
          ${pkgs.stubbe.jsonMerge {
            name = "opencode-tui-theme";
            target = "${config.home.homeDirectory}/.config/opencode/tui.json";
            patch = {
              "$schema" = "https://opencode.ai/tui.json";
              theme = "catppuccin";
            };
          }}
        '';
      }
    );
}
