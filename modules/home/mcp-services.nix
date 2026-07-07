{ self, inputs, ... }:
{
  # Long-lived MCP servers run as shared systemd user services: each serves
  # streamable HTTP on a loopback port, started once at login. Opening N Claude
  # windows then costs no extra processes — every window is just an HTTP client
  # (setup-claude-code.nix wires the matching `type = "http"` entries), so each
  # loads once for the whole session.
  #
  # The login-time httpServices are safe to share as ONE process because none
  # depends on the service's working directory: atlassian/jenkins/sentry/srv/
  # treeman resolve the caller's repo from the per-session MCP *roots* each
  # Claude window reports over its own HTTP session. That
  # per-session isolation is why they are native HTTP rather than bridged through
  # a stdio→HTTP proxy (which would collapse all windows onto one upstream
  # session and lose roots).
  #
  # The `proxied` set (playwriter + the readonly DB servers, plus nix-mcp which
  # is stateless and just folds its port onto the shared one) is the deliberate
  # inverse for playwriter/DBs: we WANT one shared upstream per backend so there
  # is exactly one browser / one DB connection. The WHOLE set is bridged through a
  # single proxy-mcp (stdio→streamable-HTTP), socket-activated on one shared
  # port, serving each backend at /<name>/mcp. proxy-mcp connects each backend
  # lazily (first request to its route) and retires it on its own idle clock, so
  # nothing runs until a window connects and the heavy browser can drop while a
  # DB stays warm — all in one process. See the unit-building block below.
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
        servers = import (self + "/lib/mcp-servers-wired.nix") {
          inherit self inputs pkgs config;
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
            Restart = "always";
            RestartSec = 2;
          };
        };

        # On-demand stdio servers (lib/mcp-servers.nix `proxied`) — the WHOLE set
        # behind ONE proxy-mcp, which does socket activation, per-upstream lazy
        # connect, per-upstream idle teardown, and process idle-exit itself. Just
        # TWO units total (not two per backend):
        #
        #   mcp-proxy.socket   loopback ListenStream on the one shared port; on
        #                      the first connection systemd starts mcp-proxy,
        #                      handing it the listening fd.
        #   mcp-proxy.service  proxy-mcp. It adopts the activation socket
        #                      ($LISTEN_FDS) instead of binding and serves every
        #                      backend at /<name>/mcp. Each backend (mode
        #                      "shared" → one stdio child shared across windows)
        #                      is connected lazily on the first request to its
        #                      route and torn down after its own options.idle
        #                      Timeout of route silence, so the heavy browser
        #                      retires while a DB stays warm. The process itself
        #                      exits after --idle-timeout of total silence,
        #                      re-arming the socket; the next connection
        #                      re-activates it and re-connects only the backend
        #                      hit.
        #
        # Type=notify: proxy-mcp signals READY=1 only once every route is
        # registered (lazy routes register immediately), holding off Accept on
        # the activation socket until then — so the activating connection waits
        # in the backlog rather than racing route registration.
        mcpProxy = "${inputs.proxy-mcp.packages.${system}.proxy-mcp}/bin/proxy-mcp";
        # proxy-mcp spawns `npx`, which needs node on PATH; the npx-fetched
        # playwriter child inherits it.
        backendPath = "PATH=${pkgs.nodejs}/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin";

        # One shared loopback addr for the whole proxied set (every entry carries
        # the same host/port; only `path` differs).
        proxyHost = (lib.head (lib.attrValues servers.proxied)).host;
        proxyPort = (lib.head (lib.attrValues servers.proxied)).port;
        # Process idle-exit floor: the longest per-upstream idle, so the process
        # outlives the last backend it might still be retiring.
        procIdleSec = lib.foldl' lib.max 0 (map (p: p.idleSec) (lib.attrValues servers.proxied));

        # ONE proxy-mcp config: the proxy server + every backend keyed by name so
        # each is served at /<name>/mcp. Per entry, mode "shared" multiplexes
        # every window onto one upstream session (one stdio child), and
        # idleTimeout makes that backend lazy + self-retiring on its own clock.
        # type must be set explicitly — proxy-mcp defaults to SSE otherwise. addr
        # is ignored under socket activation (the adopted fd wins) but kept valid
        # for config validation.
        proxyConfig = pkgs.writeText "mcp-proxy.json" (
          builtins.toJSON {
            mcpProxy = {
              baseURL = "http://${proxyHost}:${toString proxyPort}";
              addr = "${proxyHost}:${toString proxyPort}";
              name = "mcp-proxy";
              version = "1.0.0";
              type = "streamable-http";
              options.logEnabled = true;
            };
            mcpServers = lib.mapAttrs (_: p: {
              inherit (p) command args;
              options = {
                mode = "shared";
                idleTimeout = "${toString p.idleSec}s";
              };
            }) servers.proxied;
          }
        );

        # Only build the units when at least one proxied backend exists.
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
            # No [Install]: started on demand by mcp-proxy.socket.
            Service = {
              Type = "notify";
              Environment = [ backendPath ];
              # --idle-timeout: exit after procIdleSec of NO requests to any
              # route; the socket re-activates on the next connection. Per-backend
              # teardown is driven by each entry's options.idleTimeout in the
              # config. --expand-env=false: config holds literal values.
              ExecStart = "${mcpProxy} --config ${proxyConfig} --expand-env=false --idle-timeout=${toString procIdleSec}s";
              # Cold `npx` fetch of a backend can be slow on first run; allow
              # readiness up to 120s before systemd fails the start job.
              TimeoutStartSec = 120;
              # Idle-exit is a clean exit (0); only restart on actual failure.
              Restart = "on-failure";
              RestartSec = 2;
            };
          };
        };
      in
      {
        systemd.user.services = lib.mapAttrs mkService servers.httpServices // proxiedServices;
        systemd.user.sockets = proxiedSockets;

        # Re-sync httpServices on every `hm switch` so a changed server set /
        # store path is picked up even when sd-switch sees an identical unit
        # (mirrors the treemand pattern in modules/packages/treeman.nix).
        #
        # httpServices are always-on (WantedBy=default.target): use `restart`,
        # which also STARTS a stopped unit. `try-restart` is wrong here — it is a
        # no-op on a stopped unit, so when sd-switch stops a changed unit to swap
        # store paths and leaves it down, try-restart can't bring it back and the
        # server stays dead until the next login.
        #
        # mcp-proxy is deliberately NOT restarted here — it is socket-activated
        # with idle-exit, so restarting is all downside:
        #   - idle (stopped): a restart is a no-op; the next connection re-activates
        #     it on the new store paths regardless. Nothing to do.
        #   - warm (an open Claude window holds live streamable-HTTP sessions to
        #     mongodb/mysql/etc.): restarting drops those sessions, and the client
        #     does NOT re-handshake a broken `type=http` session — so the DB tools
        #     go dead mid-`hm switch` (the opposite of seamless), while the new
        #     binaries only take effect on the client's next reconnect anyway.
        # So we leave the warm proxy serving its now-stale binaries until its own
        # idle-timeout retires it; the next connection then cold-starts it on the
        # new store paths. Trade-off: a backend added to / removed from the server
        # set is not (un)served until the proxy next goes idle — routine flake
        # bumps need no restart at all. Force a pickup with
        # `systemctl --user stop mcp-proxy.service` if you must (also drops live
        # sessions).
        home.activation.restartMcpServices = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user restart ${
              lib.concatMapStringsSep " " (n: "${n}.service") (lib.attrNames servers.httpServices)
            } 2>/dev/null || true
          fi
        '';
      }
    );
}
