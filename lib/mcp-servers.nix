{
  pkgs,
  # Home directory, for building absolute --config paths in the work services.
  homeDir,
  # Absolute paths to the Go-built server binaries (flake inputs, passed by both
  # setup-claude-code.nix and mcp-services.nix). The throw defaults are lazy: a
  # consumer that never forces the matching `httpServices.*` entry need not
  # supply them.
  jenkinsMcp ? throw "lib/mcp-servers.nix: jenkinsMcp store path required",
  sentryMcp ? throw "lib/mcp-servers.nix: sentryMcp store path required",
  atlassianMcp ? throw "lib/mcp-servers.nix: atlassianMcp store path required",
  srvMcp ? throw "lib/mcp-servers.nix: srvMcp store path required",
  treemanMcp ? throw "lib/mcp-servers.nix: treemanMcp store path required",
  # Readonly DB servers, loaded as global stdio (see `global` below). Lazy
  # throws: only setup-claude-code.nix forces `global`, so mcp-services.nix
  # (which only touches httpServices/proxied) need not pass these.
  mysqlMcp ? throw "lib/mcp-servers.nix: mysqlMcp store path required",
  mongodbMcp ? throw "lib/mcp-servers.nix: mongodbMcp store path required",
  # Per-feature gates (mirror modules/features.nix). A server is wired only when
  # its backing tool/daemon is actually installed — otherwise we'd start a
  # systemd unit and advertise a client entry for a binary whose state/daemon is
  # absent. Defaults true keep callers that don't care unchanged; when a gate is
  # false the matching entry vanishes and its *Mcp throw is never forced.
  enableSrv ? true,
  enableTreeman ? true,
  enableChrome ? true,
}:
let
  inherit (pkgs) lib;
  # Canonical MCP server definitions, split by how each is loaded into Claude
  # Code. Consumed by:
  #   modules/home/mcp-services.nix
  #     - `httpServices` → one systemd user service per entry (the server serves
  #       HTTP itself; `env`/`args` configure it), started at login.
  #     - `proxied`      → a .socket + a socket-activated proxy-mcp service per
  #       entry (stdio→streamable-HTTP bridge), started on demand.
  #   modules/activation/_non-privileged/setup-claude-code.nix
  #     - `httpServices` + `proxied` → global type:"http" client entries.
  #     - `global`       → top-level stdio entries.
  #
  # The split follows two axes — how a server learns the caller's repo, and how
  # its process is best shared:
  #
  #
  #   httpServices  long-lived shared HTTP servers, one process each, started at
  #                 login. Every Claude window is just an HTTP client, so opening
  #                 N windows costs no extra process. Two kinds live here and
  #                 both are safe to share because they are NOT tied to the
  #                 process cwd:
  #                   • nix-mcp — stateless; cwd-irrelevant.
  #                   • atlassian/jenkins/sentry/srv/treeman — cwd-sensitive in
  #                     spirit, but they resolve the caller's repo/worktree from
  #                     the per-session MCP *roots* (the launch dir each Claude
  #                     window reports over its own HTTP session) or an
  #                     X-Repo-Root header, not the server's cwd. So one shared
  #                     server serves every worktree correctly. This is why they
  #                     are NATIVE http (a direct per-window session): a
  #                     stdio→HTTP bridge would collapse all windows onto one
  #                     upstream session and lose per-session roots.
  #                     srv/treeman additionally shell out to `docker` and read
  #                     ~/.config state, so their service env carries
  #                     XDG_CONFIG_HOME and a docker-reaching PATH (see
  #                     mcp-services.nix). They moved here from `global` once
  #                     their `mcp --http` mode landed.
  #
  #   proxied       a single shared stdio server fronted by proxy-mcp
  #                 (stdio→streamable-HTTP) and started ON DEMAND via systemd
  #                 socket activation. chrome-devtools lives here: we want
  #                 exactly ONE browser, so every Claude window is an HTTP client
  #                 of one proxy-mcp that owns one `npx chrome-devtools` stdio
  #                 child (mode "shared": proxy-mcp multiplexes every window onto
  #                 one upstream session, so one browser). The accepted tradeoff
  #                 vs. the old per-window model: windows share one browser
  #                 session rather than each driving their own. modules/home/
  #                 mcp-services.nix turns each entry into a .socket + a
  #                 socket-activated proxy-mcp service (it adopts the socket fd
  #                 and idle-exits), so nothing (no node process, no browser)
  #                 runs until a window first connects, and it all stops `idleSec`
  #                 after the last request.
  #
  #   global        per-window stdio, loaded everywhere. Currently empty: srv and
  #                 treeman moved to httpServices once they grew roots-aware
  #                 `mcp --http` modes. Note: a stdio server's process spawns
  #                 eagerly at session start (`alwaysLoad:false` only defers the
  #                 tool schema, not the process), and MCP servers resolve only
  #                 at launch — no skill/hook can hot-add one — so per-window
  #                 stdio is the floor for any server that lands back here.
  #
  # Every npx command is version-pinned (no `@latest`) so a spawn never makes an
  # npm "is there a newer version?" round-trip.

  # Build a work-server HTTP service entry. The server serves streamable HTTP at
  # http://127.0.0.1:<port>/mcp and reads its instance config (URLs + tokens)
  # from ~/.config/<name>-mcp/config.json (decrypted by
  # modules/files/mcp-secrets.nix from the sops blob in secrets/<name>-mcp).
  mkWork =
    {
      exe,
      port,
      name,
    }:
    {
      inherit exe port;
      host = "127.0.0.1";
      path = "/mcp";
      env = { };
      args = [
        "--http=127.0.0.1:${toString port}"
        "--config"
        "${homeDir}/.config/${name}/config.json"
      ];
    };

  httpServices = {
    # mcp-nixos (FastMCP) in its own HTTP mode; cwd-irrelevant. Configured by
    # MCP_NIXOS_* env rather than flags.
    nix-mcp = {
      exe = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      host = "127.0.0.1";
      port = 39101;
      path = "/mcp";
      env = {
        MCP_NIXOS_TRANSPORT = "http";
        MCP_NIXOS_HOST = "127.0.0.1";
        MCP_NIXOS_PORT = "39101";
        MCP_NIXOS_PATH = "/mcp";
      };
      args = [ ];
    };
    atlassian-mcp = mkWork {
      exe = atlassianMcp;
      port = 39102;
      name = "atlassian-mcp";
    };
    jenkins-mcp = mkWork {
      exe = jenkinsMcp;
      port = 39103;
      name = "jenkins-mcp";
    };
    sentry-mcp = mkWork {
      exe = sentryMcp;
      port = 39104;
      name = "sentry-mcp";
    };
  }
  # srv/treeman: native `mcp --http` daemons, gated on their own feature flags
  # so we never start a unit whose CLI + state daemon (srv-daemon / treemand)
  # the host opted out of. Unlike the work servers they take no --config (state
  # lives in ~/.config, reached via XDG_CONFIG_HOME) and shell out to `docker`
  # (PATH widened in mcp-services.nix). Repo/worktree comes from per-session MCP
  # roots / X-Repo-Root, so one process serves all windows. Ports continue the
  # 391xx block (39105/06 belong to chrome-devtools in `proxied`).
  // lib.optionalAttrs enableSrv {
    srv-mcp = {
      exe = srvMcp;
      host = "127.0.0.1";
      port = 39107;
      path = "/mcp";
      env = {
        XDG_CONFIG_HOME = "${homeDir}/.config";
      };
      args = [
        "mcp"
        "--http=127.0.0.1:39107"
        "--http-path=/mcp"
      ];
    };
  }
  // lib.optionalAttrs enableTreeman {
    treeman-mcp = {
      exe = treemanMcp;
      host = "127.0.0.1";
      port = 39108;
      path = "/mcp";
      # `--http=<addr>` both enables HTTP and sets the bind addr; path defaults
      # to /mcp. (The TREEMAN_MCP_HTTP_ADDR env is NOT honored — verified — so
      # the addr must be passed on the flag.)
      env = {
        XDG_CONFIG_HOME = "${homeDir}/.config";
      };
      args = [
        "mcp"
        "--http=127.0.0.1:39108"
      ];
    };
  };

  # Single shared stdio servers fronted by proxy-mcp and socket-activated.
  #   port        public loopback port the .socket listens on; Claude's http
  #               client connects to http://host:port<path>. proxy-mcp adopts
  #               this socket's fd directly (no private backend port needed).
  #   path        the streamable-HTTP route proxy-mcp serves this server at:
  #               `/<serverKey>/mcp`, where serverKey is the attr name below (it
  #               keys the generated proxy-mcp config in mcp-services.nix).
  #               Keep this in sync with the attr name.
  #   idleSec     proxy-mcp --idle-timeout; after that long with no requests the
  #               proxy exits (killing node + the browser); the socket re-arms
  #               and the next connection restarts it.
  #   command/args the stdio server proxy-mcp wraps (one shared instance, mode
  #               "shared"); they become the `command`/`args` of this server's
  #               entry in the generated proxy-mcp config.json.
  # chrome-devtools gated on enableChrome (features.browsers): --auto-connect
  # drives a real Chrome, useless on a host with no browser installed.
  #
  # mysql/mongodb (readonly DB servers) join the SAME pattern, ungated: exactly
  # one process each, socket-activated, idle-exiting after idleSec. proxied (not
  # httpServices) is the right home precisely because of idle-exit — a source
  # with an `ssh` block holds an SSH tunnel open for the life of the process, so
  # a login-time httpService would keep the staging tunnel up 24/7; here the
  # tunnel (and the process) die idleSec after the last query and re-establish
  # on the next. mode "shared" multiplexes every window onto one upstream
  # session, which is fine: each tool call is an independent query, no
  # per-session state to collapse. mysql `--read-only` force-readonlies every
  # source on top of the per-source flag; mongodb-mcp enforces readonly per
  # source. Configs decrypt from sops (modules/files/mcp-secrets.nix) to
  # ~/.config/<name>-mcp/config.json. Ports continue the 391xx block (39105
  # chrome, 39107/08 srv/treeman → 39109/10 here).
  proxied =
    lib.optionalAttrs enableChrome {
      chrome-devtools = {
        host = "127.0.0.1";
        port = 39105;
        path = "/chrome-devtools/mcp";
        idleSec = 300;
        command = "npx";
        args = [
          "-y"
          "chrome-devtools-mcp@1.4.0"
          "--no-usage-statistics"
          "--auto-connect"
        ];
      };
    }
    // {
      mysql = {
        host = "127.0.0.1";
        port = 39109;
        path = "/mysql/mcp";
        idleSec = 300;
        command = mysqlMcp;
        args = [
          "serve"
          "--read-only"
          "--config"
          "${homeDir}/.config/mysql-mcp/config.json"
        ];
      };
      mongodb = {
        host = "127.0.0.1";
        port = 39110;
        path = "/mongodb/mcp";
        idleSec = 300;
        command = mongodbMcp;
        args = [
          "--config"
          "${homeDir}/.config/mongodb-mcp/config.json"
        ];
      };
    };

  # Per-window stdio servers, loaded everywhere. Empty since srv/treeman became
  # shared HTTP daemons and the DB servers moved to `proxied`; kept as an
  # explicit category so a future stdio-only server has an obvious home (and
  # setup-claude-code.nix still maps it).
  global = { };
in
{
  inherit
    httpServices
    proxied
    global
    ;
}
