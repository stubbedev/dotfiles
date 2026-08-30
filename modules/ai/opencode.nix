# opencode CLI.
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
        # opencode ships its own LSP client with 37 built-in servers, but `lsp`
        # is off unless configured, so until now it edited blind -- no
        # diagnostics, same gap modules/ai/claude-code.nix just closed.
        #
        # Each built-in looks its binary up on PATH first and only then falls
        # back to fetching one (a GitHub release tarball, `go install`, `gem
        # install`, an npm package). So the fix is a PATH, not a config table:
        # put the servers we already build in front of it and every built-in
        # resolves to a store path. That deliberately beats overriding each
        # server's `command` -- the built-ins carry root-marker and spawn logic
        # worth keeping (typescript resolves the *project's* tsserver.js, gopls
        # prefers go.work over go.mod, pyright/ty pick up a .venv), and an
        # override would replace it.
        #
        # Same attrs as modules/nvim.nix and claude-code.nix, so no new closure.
        # Only servers whose built-in resolves them by PATH name are listed:
        # typescript, astro, oxlint, biome and eslint deliberately resolve out
        # of the project's own node_modules, and nothing here would change that.
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
          # --suffix, not --prefix: a project that pins its own server in
          # node_modules/.bin or a devshell should still win.
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

        # `lsp` defaults to off. An object turns EVERY built-in on and then
        # applies these entries on top, so the two below are the only places
        # this disagrees with upstream -- the rest of the table is opencode's.
        #
        # Unlike Claude Code, opencode starts every server whose extensions
        # match, not just the first, so a PHP file would otherwise get two.
        #
        # .jsonc, not .json: opencode reads config.json, then opencode.json,
        # then opencode.jsonc, merging each over the last -- so the .jsonc is
        # the one that wins, and opencode writes an empty stub there itself.
        # Owning that filename keeps anything opencode puts in it from silently
        # overriding this file; `force` replaces the stub, which holds nothing
        # but a `$schema` line. Contents stay plain JSON -- JSONC is a superset
        # (their parser only adds comments and trailing commas), so there is
        # nothing to convert and pkgs.formats needs no jsonc generator.
        xdg.configFile."opencode/opencode.jsonc" = {
          force = true;
          source = (pkgs.formats.json { }).generate "opencode.jsonc" {
            "$schema" = "https://opencode.ai/config.json";

            # The same inventory Claude and Codex load, in opencode's spelling.
            # This file is the merge winner (see the .jsonc note above), so the
            # managed set fully owns `mcp` -- servers dropped from
            # modules/ai/mcp-servers.nix disappear here too, matching the
            # authoritative .mcpServers write in modules/ai/claude-code.nix.
            mcp = config.stubbe.mcp.clients.opencode;

            lsp = {
              # phpantom is the PHP server everything else here uses; the
              # built-in wants `intelephense` on PATH and npm-installs it
              # otherwise. No built-in to inherit from, so spell out the
              # extensions -- .blade.php matches on its trailing .php.
              phpantom = {
                command = [ (lib.getExe' pkgs.phpantom_lsp "phpantom_lsp") ];
                extensions = [ ".php" ];
              };
              "php intelephense".disabled = true;

              # The built-in looks for `docker-langserver` -- the node server
              # modules/nvim.nix dropped for Docker's own Go binary, which
              # covers Dockerfile and compose in one process. Override rather
              # than add the node one back; `extensions` is omitted so the
              # built-in's own list still applies.
              #
              # This reaches *.dockerfile only. opencode picks a server with
              # `path.parse(file).ext || file`, so for an extensionless file
              # the lookup key becomes the whole path and the built-in's own
              # "Dockerfile" entry can never equal it -- verified: editing a
              # file named Dockerfile yields no diagnostics from any server.
              # Upstream bug, not one the config can route around.
              dockerfile.command = [
                (lib.getExe' pkgs.docker-language-server "docker-language-server")
                "start"
                "--stdio"
              ];
            };
          };
        };

        # opencode reports only `severity === 1` after an edit -- see the
        # plugin's own header. Dropped into the global plugin directory, which
        # opencode globs as `{plugin,plugins}/*.{ts,js}` with symlinks
        # followed, so a store symlink is loaded like a real file.
        xdg.configFile."opencode/plugins/lsp-warnings.js".source =
          ../../src/opencode/plugins/lsp-warnings.js;

        # The theme lives in tui.json, not opencode.json (opencode.ai/docs/
        # themes). "catppuccin" is the built-in whose dark variant IS Mocha --
        # byte-identical to pkgs.stubbe.colors (base 1e1e2e, mauve cba6f7, …),
        # so it matches alacritty (modules/terminal.nix) with no third copy of
        # the palette here; a truecolor terminal resolves the dark variant.
        # tui.json's `theme` also overrides the kv store the TUI's /theme
        # command writes its choice to, so this pin survives every interactive
        # detour.
        #
        # jsonMerge, not a symlink: tui.json also carries user keybinds, and a
        # merge patches the live file so anything written between evaluation
        # and activation survives.
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
