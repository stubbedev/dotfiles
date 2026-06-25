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
  # mcp-proxy (stdio→streamable-HTTP) and socket-activated, so nothing runs until
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
        # entry becomes three units so exactly one instance ever runs, started
        # only when a Claude window first connects and torn down `idleSec` after
        # the last one disconnects:
        #
        #   mcp-<name>.socket          loopback ListenStream on the public port;
        #                              activates the frontend on first connect.
        #   mcp-<name>.service         systemd-socket-proxyd forwarding the
        #                              activated socket to the backend's private
        #                              port. --exit-idle-time makes it exit once
        #                              all proxied connections close and stay
        #                              closed for idleSec.
        #   mcp-<name>-backend.service mcp-proxy serving streamable-HTTP, wrapping
        #                              the one shared `command` stdio child.
        #                              StopWhenUnneeded ties its life to the
        #                              frontend: when the frontend idle-exits and
        #                              nothing else requires the backend, systemd
        #                              stops it, killing node + the browser.
        #
        # Ordering/race: the frontend Requires+After the backend, and the
        # backend's ExecStartPost blocks until mcp-proxy is actually listening on
        # backendPort. Since ExecStartPost is part of the start job, `After`
        # waits for it — so socket-proxyd never forwards to a not-yet-bound port.
        #
        # mcp-proxy here is TBXark/mcp-proxy (Go, via modules/overlays.nix). It is
        # config-file driven, not CLI-args driven: it takes `-config <file>` whose
        # mcpProxy.addr is the bind address and whose mcpServers map defines the
        # wrapped stdio child. It serves each server at `/<serverKey>/mcp`
        # (streamable-HTTP), which is why the client `path` is `/<name>/mcp`.
        mcpProxy = "${pkgs.mcp-proxy}/bin/mcp-proxy";
        socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
        # mcp-proxy spawns `npx`, which needs node on PATH; the npx-fetched
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

        proxiedFrontends = lib.mapAttrs' (
          name: p:
          lib.nameValuePair "mcp-${name}" {
            Unit = {
              Description = "${name} MCP proxy frontend (socket-proxyd)";
              Requires = [ "mcp-${name}-backend.service" ];
              After = [ "mcp-${name}-backend.service" ];
            };
            Service.ExecStart = "${socketProxyd} --exit-idle-time=${toString p.idleSec}s ${p.host}:${toString p.backendPort}";
          }
        ) servers.proxied;

        # TBXark mcp-proxy config per backend: bind addr + the single wrapped
        # stdio server, keyed by the entry name so it is served at /<name>/mcp.
        # type must be set explicitly — mcp-proxy defaults to SSE otherwise.
        mkProxyConfig =
          name: p:
          pkgs.writeText "mcp-${name}-proxy.json" (
            builtins.toJSON {
              mcpProxy = {
                addr = "${p.host}:${toString p.backendPort}";
                type = "streamable-http";
                options.logEnabled = true;
              };
              mcpServers.${name} = {
                inherit (p) command args;
              };
            }
          );

        proxiedBackends = lib.mapAttrs' (
          name: p:
          lib.nameValuePair "mcp-${name}-backend" {
            Unit.Description = "${name} MCP proxy backend (mcp-proxy → ${p.command})";
            Service = {
              Type = "simple";
              StopWhenUnneeded = true;
              Environment = [ backendPath ];
              # -expand-env=false: config holds literal values, no $VAR expansion.
              ExecStart = "${mcpProxy} -config ${mkProxyConfig name p} -expand-env=false";
              # Gate readiness on the port actually accepting connections so the
              # socket-activated frontend doesn't race a cold `npx` start.
              ExecStartPost = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 300); do (exec 3<>/dev/tcp/${p.host}/${toString p.backendPort}) 2>/dev/null && exit 0; sleep 0.3; done; exit 1'";
              TimeoutStartSec = 120;
              Restart = "on-failure";
              RestartSec = 2;
            };
          }
        ) servers.proxied;
      in
      {
        systemd.user.services =
          lib.mapAttrs mkService servers.httpServices // proxiedFrontends // proxiedBackends;
        systemd.user.sockets = proxiedSockets;

        # Restart on every `hm switch` so a changed server set / store path is
        # picked up even when sd-switch sees an identical unit (mirrors the
        # treemand pattern in modules/packages/treeman.nix). try-restart only
        # touches units already running, so socket-activated backends that are
        # idle stay down until the next connection.
        home.activation.restartMcpServices = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user try-restart ${
              lib.concatMapStringsSep " " (n: "${n}.service") (
                lib.attrNames servers.httpServices ++ map (n: "mcp-${n}-backend") (lib.attrNames servers.proxied)
              )
            } 2>/dev/null || true
          fi
        '';
      }
    );
}
