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
      servers = import (self + "/lib/mcp-servers-wired.nix") {
        inherit
          self
          inputs
          pkgs
          config
          ;
      };

      # http client entries → the shared HTTP services (modules/home/
      # mcp-services.nix). No per-window subprocess: every window reuses the one
      # warm process and is scoped to its repo by the X-Repo-Root header below.
      #
      # The header is what keeps the shared-process model alive. MCP *roots* —
      # the server asking each window "which workspace are you?" over its own
      # session — did the same job and still does today, but MCP 2026-07-28
      # (SEP-2322/2575) forbids server→client requests, so roots/list stops
      # working the moment Claude Code negotiates that revision. Every
      # roots-dependent server would then fail every cwd-relative call at once.
      #
      # `\${PWD}` stays a literal in the generated JSON; Claude Code expands it
      # per window at launch (env-var expansion is supported in `headers`), so
      # each window reports its own launch dir — the same value roots carried.
      # Servers rank this header ABOVE roots, so today it changes nothing.
      httpServers = lib.mapAttrs (_: s: {
        type = "http";
        url = "http://${s.host}:${toString s.port}${s.path}";
        headers."X-Repo-Root" = "\${PWD}";
      }) servers.httpServices;

      # http client entries → the socket-activated proxy-mcp frontends (same
      # module). Connecting here is what spawns the single shared backend on
      # demand; every window points at the one port.
      #
      # Same X-Repo-Root header as above. It matters most here: the
      # `perSession` backends (jenkins/sentry) are gated by repoWhitelist,
      # which proxy-mcp evaluates against the caller's repo — sourced from
      # roots until now. A whitelist that can no longer see the repo fails
      # CLOSED (tools hidden), so without the header those two would go dark
      # on every repo the day Claude Code moves to 2026-07-28. Inert for the
      # cwd-irrelevant backends (chrome-devtools/ds/nix-mcp/pty-mcp).
      proxiedServers = lib.mapAttrs (_: p: {
        type = "http";
        url = "http://${p.host}:${toString p.port}${p.path}";
        headers."X-Repo-Root" = "\${PWD}";
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
            model = "claude-opus-5";
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
