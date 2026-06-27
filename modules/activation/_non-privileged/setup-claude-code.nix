{ self, inputs, ... }:
{
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      lib,
      pkgs,
      homeLib,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      servers = import (self + "/lib/mcp-servers.nix") {
        inherit pkgs;
        homeDir = config.home.homeDirectory;
        # Go-built work servers from flake inputs → offline store-path spawn.
        jenkinsMcp = "${inputs."jenkins-mcp".packages.${system}.default}/bin/jenkins-mcp";
        sentryMcp = "${inputs."sentry-mcp".packages.${system}.default}/bin/sentry-mcp";
        atlassianMcp = "${inputs."atlassian-mcp".packages.${system}.default}/bin/atlassian-mcp";
        laravelMcp = "${inputs."laravel-dev-mcp".packages.${system}.default}/bin/laravel-dev-mcp";
        srvMcp = "${inputs.srv.packages.${system}.srv}/bin/srv";
        treemanMcp = "${inputs.treeman.packages.${system}.treeman}/bin/treeman";
        # Readonly DB servers → global stdio entries (Go bins from flake inputs).
        nixMcp = "${inputs."nix-mcp".packages.${system}.default}/bin/nix-mcp";
        mysqlMcp = "${inputs."mysql-mcp".packages.${system}.default}/bin/mysql-mcp";
        mongodbMcp = "${inputs."mongodb-mcp".packages.${system}.default}/bin/mongodb-mcp";
        # Gate client entries on the same feature flags mcp-services.nix uses to
        # gate the services, so we never advertise a server that isn't running.
        enableSrv = config.features.srv;
        enableTreeman = config.features.treeman;
        enableChrome = config.features.browsers;
        enablePhp = config.features.php;
      };

      # http client entries → the shared HTTP services (modules/home/
      # mcp-services.nix). No per-window subprocess: every window reuses the one
      # warm process and is scoped to its repo via per-session MCP roots.
      httpServers = lib.mapAttrs (_: s: {
        type = "http";
        url = "http://${s.host}:${toString s.port}${s.path}";
      }) servers.httpServices;

      # http client entries → the socket-activated proxy-mcp frontends (same
      # module). Connecting here is what spawns the single shared backend on
      # demand; every window points at the one port.
      proxiedServers = lib.mapAttrs (_: p: {
        type = "http";
        url = "http://${p.host}:${toString p.port}${p.path}";
      }) servers.proxied;

      # Claude's stdio shape: { type, command, args, env? }
      toStdio =
        _: server:
        {
          type = "stdio";
          inherit (server) command args;
        }
        // lib.optionalAttrs (server ? env) { inherit (server) env; };

      # global bucket → ordinary per-window stdio entries, loaded everywhere.
      stdioServers = lib.mapAttrs toStdio servers.global;

      # Top-level mcpServers in every window = http services + on-demand proxied
      # + global stdio.
      globalMcpServers = httpServers // proxiedServers // stdioServers;
    in
    {
      actionScript = ''
        ${homeLib.mergeJsonPatch {
          name = "claude-settings-patch";
          target = "${config.home.homeDirectory}/.claude/settings.json";
          patch = {
            statusLine = {
              type = "command";
              command = "cship";
              refreshInterval = 5;
            };
            includeCoAuthoredBy = false;
            tui = "fullscreen";
            editorMode = "vi";
            model = "claude-opus-4-8[1m]";
            # Use the PHPantom language server for .php instead of the
            # official php-lsp plugin. Local marketplace lives in the
            # live src checkout; the phpantom_lsp binary is on PATH via
            # modules/packages/php.nix.
            extraKnownMarketplaces = {
              phpantom.source = {
                source = "directory";
                path = "${config.home.homeDirectory}/.stubbe/src/claude/phpantom-lsp";
              };
              # Caveman: ultra-compressed comms mode. Plugin self-registers
              # its SessionStart/UserPromptSubmit hooks via plugin.json
              # (${CLAUDE_PLUGIN_ROOT}), so enabling it here is enough — no
              # need to wire hooks in settings.json. Default mode is "full"
              # (caveman-config.js), so every session starts caveman-on.
              caveman.source = {
                source = "github";
                repo = "JuliusBrussee/caveman";
              };
              # Ponytail: minimal-code-gen discipline (YAGNI decision ladder,
              # fewer LOC). Orthogonal to caveman — caveman compresses prose,
              # ponytail constrains the code written. Self-registers its
              # lifecycle hooks via the plugin manifest; needs node on PATH.
              ponytail.source = {
                source = "github";
                repo = "DietrichGebert/ponytail";
              };
            };
            enabledPlugins = {
              "phpantom-lsp@phpantom" = true;
              "php-lsp@claude-plugins-official" = false;
              "caveman@caveman" = true;
              "ponytail@ponytail" = true;
            };
          };
        }}

        ${homeLib.mergeJsonPatch {
          name = "caveman-config";
          # caveman-config.js resolves $XDG_CONFIG_HOME/caveman/config.json,
          # falling back to ~/.config/caveman/config.json. Pin defaultMode so
          # caveman starts "full" on every session regardless of the plugin's
          # built-in default drifting in a future update.
          target = "${config.home.homeDirectory}/.config/caveman/config.json";
          patch.defaultMode = "full";
        }}

        ${homeLib.mergeJsonPatch {
          name = "ponytail-config";
          # Ponytail resolves ~/.config/ponytail/config.json (or
          # $PONYTAIL_DEFAULT_MODE). Pin defaultMode so every session starts at
          # a known intensity regardless of the plugin's built-in default.
          target = "${config.home.homeDirectory}/.config/ponytail/config.json";
          patch.defaultMode = "full";
        }}

        ${homeLib.setJsonKey {
          name = "claude-config-mcp";
          target = "${config.home.homeDirectory}/.claude.json";
          key = "mcpServers";
          # Authoritative: the managed set fully owns .mcpServers, so servers
          # dropped from lib/mcp-servers.nix disappear instead of lingering.
          value = globalMcpServers;
        }}
      '';
    };
}
