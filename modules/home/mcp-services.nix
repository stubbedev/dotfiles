{ self, inputs, ... }:
{
  # Long-lived MCP servers run as shared systemd user services: each serves
  # streamable HTTP on a loopback port, started once at login. Opening N Claude
  # windows then costs no extra processes — every window is just an HTTP client
  # (setup-claude-code.nix wires the matching `type = "http"` entries), and the
  # heavy ones (nix-mcp's NixOS option index) load once for the whole session.
  #
  # The login-time httpServices are safe to share as ONE process because none
  # depends on the service's working directory: nix-mcp is stateless, and
  # atlassian/jenkins/sentry resolve the caller's repo from the per-session MCP
  # *roots* each Claude window reports over its own HTTP session. That
  # per-session isolation is why they are native HTTP rather than bridged through
  # a stdio→HTTP proxy (which would collapse all windows onto one upstream
  # session and lose roots).
  #
  # The `proxied` set (chrome-devtools) is the deliberate inverse: we WANT one
  # shared upstream so there is exactly one browser. It is bridged through
  # proxy-mcp (stdio→streamable-HTTP) and socket-activated, so nothing runs until
  # a window connects and it stops once they all close. See the unit-building
  # block below.
  flake.modules.homeManager.mcpServices =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.claudeCode (
      let
        system = pkgs.stdenv.hostPlatform.system;
        servers = import (self + "/lib/mcp-servers.nix") {
          inherit pkgs;
          homeDir = config.home.homeDirectory;
          jenkinsMcp = "${inputs."jenkins-mcp".packages.${system}.default}/bin/jenkins-mcp";
          sentryMcp = "${inputs."sentry-mcp".packages.${system}.default}/bin/sentry-mcp";
          atlassianMcp = "${inputs."atlassian-mcp".packages.${system}.default}/bin/atlassian-mcp";
          srvMcp = "${inputs.srv.packages.${system}.srv}/bin/srv";
          treemanMcp = "${inputs.treeman.packages.${system}.treeman}/bin/treeman";
          # Readonly DB servers now live in `proxied` (socket-activated, shared,
          # idle-exit), which this module forces — so their binaries must be
          # passed here too, not just in setup-claude-code.nix.
          mysqlMcp = "${inputs."mysql-mcp".packages.${system}.default}/bin/mysql-mcp";
          mongodbMcp = "${inputs."mongodb-mcp".packages.${system}.default}/bin/mongodb-mcp";
          enableSrv = config.features.srv;
          enableTreeman = config.features.treeman;
          enableChrome = config.features.browsers;
        };

        # Shared service PATH. The work servers shell out to `git` (repo
        # detection from MCP roots); srv/treeman additionally shell out to
        # `docker`. The server binaries themselves are absolute store paths and
        # need nothing. /run/wrappers/bin + /usr/local/bin mirror srv-daemon so
        # the docker client is found on both NixOS and standalone-HM hosts.
        pathEnv = "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";

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
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        # On-demand singleton stdio servers (lib/mcp-servers.nix `proxied`). Each
        # entry becomes just TWO units — proxy-mcp now does socket activation and
        # idle-exit itself, so the old systemd-socket-proxyd frontend + private
        # backend port are gone:
        #
        #   mcp-<name>.socket   loopback ListenStream on the public port; on the
        #                       first connection systemd starts the matching
        #                       service, handing it the listening fd.
        #   mcp-<name>.service  proxy-mcp. It adopts the activation socket
        #                       ($LISTEN_FDS) instead of binding, serves the one
        #                       shared stdio child (mode "shared" → exactly one
        #                       browser across all windows), and exits itself
        #                       after `idleSec` of no requests (--idle-timeout).
        #                       The socket stays armed, so the next connection
        #                       re-activates it; node + the browser die on exit.
        #
        # Type=notify: proxy-mcp signals READY=1 only after the upstream stdio
        # child connects and its route is registered, and it holds off Accept on
        # the activation socket until then — so the connection that triggered
        # activation waits in the socket backlog through the cold `npx` start
        # rather than racing route registration. It serves each server at
        # `/<serverKey>/mcp`, which is why the client `path` is `/<name>/mcp`.
        mcpProxy = "${inputs.proxy-mcp.packages.${system}.proxy-mcp}/bin/proxy-mcp";
        # proxy-mcp spawns `npx`, which needs node on PATH; the npx-fetched
        # chrome-devtools child inherits it.
        backendPath = "PATH=${pkgs.nodejs}/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin";

        proxiedSockets = lib.mapAttrs' (
          name: p:
          lib.nameValuePair "mcp-${name}" {
            Unit.Description = "${name} MCP proxy socket (on-demand activation)";
            Socket.ListenStream = "${p.host}:${toString p.port}";
            Install.WantedBy = [ "sockets.target" ];
          }
        ) servers.proxied;

        # proxy-mcp config per entry: the proxy server + the single wrapped stdio
        # child, keyed by the entry name so it is served at /<name>/mcp. mode
        # "shared" multiplexes every Claude window onto one upstream session →
        # one stdio child (one browser). type must be set explicitly — proxy-mcp
        # defaults to SSE otherwise. addr is ignored under socket activation (the
        # adopted fd wins) but kept valid for config validation.
        mkProxyConfig =
          name: p:
          pkgs.writeText "mcp-${name}-proxy.json" (
            builtins.toJSON {
              mcpProxy = {
                baseURL = "http://${p.host}:${toString p.port}";
                addr = "${p.host}:${toString p.port}";
                name = "${name}-proxy";
                version = "1.0.0";
                type = "streamable-http";
                options.logEnabled = true;
              };
              mcpServers.${name} = {
                inherit (p) command args;
                options.mode = "shared";
              };
            }
          );

        proxiedServices = lib.mapAttrs' (
          name: p:
          lib.nameValuePair "mcp-${name}" {
            Unit.Description = "${name} MCP proxy (proxy-mcp → ${p.command}, socket-activated)";
            # No [Install]: started on demand by mcp-${name}.socket.
            Service = {
              Type = "notify";
              Environment = [ backendPath ];
              # --idle-timeout: exit after idleSec of no proxied requests; the
              # socket re-activates on the next connection. --expand-env=false:
              # config holds literal values, no $VAR expansion.
              ExecStart = "${mcpProxy} --config ${mkProxyConfig name p} --expand-env=false --idle-timeout=${toString p.idleSec}s";
              # Cold `npx` fetch of the upstream can be slow on first run; allow
              # readiness up to 120s before systemd fails the start job.
              TimeoutStartSec = 120;
              # Idle-exit is a clean exit (0); only restart on actual failure.
              Restart = "on-failure";
              RestartSec = 2;
            };
          }
        ) servers.proxied;
      in
      {
        systemd.user.services = lib.mapAttrs mkService servers.httpServices // proxiedServices;
        systemd.user.sockets = proxiedSockets;

        # Restart on every `hm switch` so a changed server set / store path is
        # picked up even when sd-switch sees an identical unit (mirrors the
        # treemand pattern in modules/packages/treeman.nix). try-restart only
        # touches units already running, so socket-activated proxies that are
        # idle stay down until the next connection.
        home.activation.restartMcpServices = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user try-restart ${
              lib.concatMapStringsSep " " (n: "${n}.service") (
                lib.attrNames servers.httpServices ++ map (n: "mcp-${n}") (lib.attrNames servers.proxied)
              )
            } 2>/dev/null || true
          fi
        '';
      }
    );
}
