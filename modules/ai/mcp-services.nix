{ inputs, ... }:
{
  flake.modules.homeManager.mcpServices =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config.features.claudeCode || config.features.codex) (
      let
        system = pkgs.stdenv.hostPlatform.system;
        proxyEnvPath = "${config.home.homeDirectory}/.config/mcp-proxy/proxy.env";
        inherit (config.stubbe.mcp) servers;

        pathEnv = "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin";

        mkService = name: s: {
          Unit = {
            Description = "${name} MCP server (shared HTTP)";
            After = [ "default.target" ];
          };
          Install.WantedBy = [ "default.target" ];
          Service = {
            Type = "simple";
            Environment = [ pathEnv ] ++ lib.mapAttrsToList (k: v: "${k}=${v}") s.env;
            ExecStart = "${s.exe} ${lib.escapeShellArgs s.args}";
            Restart = "always";
            RestartSec = 2;
          };
        };

        mcpProxy = "${inputs.proxy-mcp.packages.${system}.proxy-mcp}/bin/proxy-mcp";
        backendPath = "PATH=${pkgs.nodejs}/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin";

        proxyHost = (lib.head (lib.attrValues servers.proxied)).host;
        proxyPort = (lib.head (lib.attrValues servers.proxied)).port;
        procIdleSec = lib.foldl' lib.max 0 (map (p: p.idleSec) (lib.attrValues servers.proxied));

        # `type` must be explicit or proxy-mcp defaults to SSE. `addr` is ignored
        # under socket activation but has to stay valid for config validation.
        proxyConfig = pkgs.stubbe.gen.json "mcp-proxy.json" {
          mcpProxy = {
            baseURL = "http://${proxyHost}:${toString proxyPort}";
            addr = "${proxyHost}:${toString proxyPort}";
            name = "mcp-proxy";
            version = "1.0.0";
            type = "streamable-http";
            options.logEnabled = true;
          };
          mcpServers = lib.mapAttrs (
            _: p:
            (
              if p ? url then
                {
                  inherit (p) url;
                  transportType = p.transportType or "streamable-http";
                }
              else
                { inherit (p) command args; }
            )
            // {
              options = {
                mode = p.mode or "shared";
                idleTimeout = "${toString p.idleSec}s";
              }
              // lib.optionalAttrs (p ? repoWhitelist) { inherit (p) repoWhitelist; };
            }
          ) servers.proxied;
        };

        proxiedSockets = lib.optionalAttrs (servers.proxied != { }) {
          mcp-proxy = {
            Unit.Description = "MCP proxy socket (on-demand activation)";
            Socket.ListenStream = "${proxyHost}:${toString proxyPort}";
            Install.WantedBy = [ "sockets.target" ];
          };
        };

        proxiedServices = lib.optionalAttrs (servers.proxied != { }) {
          mcp-proxy = {
            Unit.Description = "MCP proxy (proxy-mcp → ${toString (lib.attrNames servers.proxied)}, socket-activated)";
            Service = {
              # notify holds off Accept until every route is registered, so the
              # activating connection waits in the backlog instead of racing it.
              Type = "notify";
              Environment = [ backendPath ];
              # Leading `-` so a missing secret leaves the gate values unset and
              # every gated backend fails closed, rather than stopping the proxy
              # the ungated backends also depend on.
              EnvironmentFile = "-${proxyEnvPath}";
              # --expand-env is global: no other config value may contain a
              # literal `$`.
              ExecStart = "${mcpProxy} --config ${proxyConfig} --expand-env=true --idle-timeout=${toString procIdleSec}s";
              TimeoutStartSec = 120;
              Restart = "on-failure";
              RestartSec = 2;
            };
          };
        };
      in
      {
        sops.secrets = {
          mcp-proxy-env = pkgs.stubbe.secret {
            name = "mcp-proxy-env.env";
            path = proxyEnvPath;
          };
        }
        // lib.listToAttrs (
          map
            (
              provider:
              lib.nameValuePair "${provider}_mcp" (
                pkgs.stubbe.secret {
                  name = "${provider}-mcp.json";
                  path = "${config.home.homeDirectory}/.config/${provider}-mcp/config.json";
                }
              )
            )
            [
              "atlassian"
              "jenkins"
              "sentry"
              "ds"
            ]
        );

        systemd.user.services = lib.mapAttrs mkService servers.httpServices // proxiedServices;
        systemd.user.sockets = proxiedSockets;

        # sd-switch can leave a changed unit stopped, and `try-restart` is a
        # no-op on a stopped unit, so the always-on httpServices need `restart`
        # or they stay dead until the next login. mcp-proxy takes the opposite
        # verb: `restart` would cold-start an idle proxy on every switch and
        # defeat socket activation.
        stubbe.setup.restartMcpServices = {
          after = [ "reloadSystemd" ];
          script = ''
            if command -v systemctl >/dev/null 2>&1; then
              systemctl --user restart ${
                lib.concatMapStringsSep " " (n: "${n}.service") (lib.attrNames servers.httpServices)
              } 2>/dev/null || true
              ${lib.optionalString (servers.proxied != { }) ''
                systemctl --user try-restart mcp-proxy.service 2>/dev/null || true
              ''}
            fi
          '';
        };
      }
    );
}
