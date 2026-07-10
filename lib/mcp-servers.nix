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
  nixMcp ? throw "lib/mcp-servers.nix: nixMcp store path required",
  dsMcp ? throw "lib/mcp-servers.nix: dsMcp store path required",
  ptyMcp ? throw "lib/mcp-servers.nix: ptyMcp store path required",
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
  #                 N windows costs no extra process. All are safe to share as
  #                 one process because they are NOT tied to the process cwd:
  #                 atlassian/jenkins/sentry/srv/treeman are cwd-sensitive in
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
  #   proxied       shared stdio servers fronted by ONE proxy-mcp
  #                 (stdio→streamable-HTTP) and started ON DEMAND via systemd
  #                 socket activation. chrome-devtools lives here: we want
  #                 exactly ONE browser, so every Claude window is an HTTP client
  #                 of one proxy-mcp that owns one `npx chrome-devtools-mcp` stdio
  #                 child (mode "shared": proxy-mcp multiplexes every window onto
  #                 one upstream session, so one browser). The accepted tradeoff
  #                 vs. the old per-window model: windows share one browser
  #                 session rather than each driving their own. modules/home/
  #                 mcp-services.nix turns the WHOLE set into a single .socket +
  #                 a single socket-activated proxy-mcp service serving each entry
  #                 at /<name>/mcp on one shared port. proxy-mcp connects each
  #                 backend lazily on the first request to its route and retires
  #                 it `idleSec` after that route falls quiet (per-upstream
  #                 options.idleTimeout) — so the heavy browser can drop while a
  #                 DB stays warm, and vice versa — all inside one process. The
  #                 process itself idle-exits once every route is quiet, re-arming
  #                 the socket. A panic in one backend is contained, never
  #                 crashing its siblings.
  #
  #   global        per-window stdio, loaded everywhere. Currently empty: srv and
  #                 treeman moved to httpServices once they grew roots-aware
  #                 `mcp --http` modes. Note: a stdio server's process spawns
  #                 eagerly at session start (`alwaysLoad:false` only defers the
  #                 tool schema, not the process), and MCP servers resolve only
  #                 at launch — no skill/hook can hot-add one — so per-window
  #                 stdio is the floor for any server that lands back here.
  #
  # npx commands are version-pinned (no `@latest`) so a spawn never makes an
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

  # Shared stdio servers fronted by ONE socket-activated proxy-mcp. Every entry
  # is served by the same proxy process on the same `proxiedPort`, distinguished
  # by `path` (/<name>/mcp); mcp-services.nix aggregates them into one config.
  #   host/port   the single shared loopback addr the one .socket listens on and
  #               every Claude http client connects to. proxy-mcp adopts the
  #               socket fd directly (no private backend port). All entries share
  #               it; only `path` differs per server.
  #   path        the streamable-HTTP route proxy-mcp serves this server at:
  #               `/<serverKey>/mcp`, where serverKey is the attr name below (it
  #               keys the entry in the generated proxy-mcp config). Keep in sync
  #               with the attr name.
  #   idleSec     this server's per-upstream options.idleTimeout: proxy-mcp
  #               connects the backend lazily on the first request to its route
  #               and tears it down after that long with no requests TO THIS
  #               ROUTE, independently of the other backends. The whole proxy
  #               process also exits once every route is quiet (re-arming the
  #               socket); the next connection restarts the process and the one
  #               backend hit.
  #   command/args the stdio server proxy-mcp wraps (one shared instance, mode
  #               "shared"); they become this entry's `command`/`args` in the
  #               generated proxy-mcp config.json.
  # chrome-devtools gated on enableChrome (features.browsers): it drives the
  # user's real Chrome over CDP, useless on a host with no browser installed.
  # --autoConnect attaches to the already-running stable-channel Chrome instead
  # of launching its own (Chrome 144+; remote debugging must be enabled once in
  # chrome://inspect/#remote-debugging).
  #
  # ds-mcp (one readonly DB server for MySQL + MongoDB sources) joins the SAME
  # proxy, ungated. proxied (not httpServices) is the right home precisely
  # because of idle-exit — a source with an `ssh` block holds an SSH tunnel
  # open for the life of the backend, so a login-time httpService would keep
  # the staging tunnel up 24/7; here the tunnel (and the backend) die idleSec
  # after the last query and re-establish on the next, while leaving the
  # browser backend alone. mode "shared" multiplexes every window onto one
  # upstream session, which is fine: each tool call is an independent query, no
  # per-session state to collapse. `--read-only` force-readonlies every source
  # on top of the per-source flag. Config decrypts from sops
  # (modules/files/mcp-secrets.nix) to ~/.config/ds-mcp/config.json.
  proxiedPort = 39105;
  # jenkins/sentry are gated to ONE repo: only a Claude window whose workspace
  # git remote matches sees their tools. proxy-mcp's per-backend repoWhitelist
  # does the gating (matched against the client's remotes, normalized across
  # ssh/https and a trailing .git; fails closed for a client exposing no
  # workspace). They keep their native HTTP systemd units as the UPSTREAM — the
  # proxy just fronts them as url-backends in `mode "perSession"` so each
  # window's MCP roots are relayed to a dedicated upstream session (a "shared"
  # session would collapse every window's roots onto one upstream, breaking
  # per-repo resolution). The proxied entry reuses the same attr key as its
  # httpServices twin, so setup-claude-code.nix's `httpServers // proxiedServers`
  # makes the gated proxy route WIN the client entry (the direct :391xx entry is
  # overridden away). atlassian stays ungated (works in every repo).
  #
  # The remote itself is NOT hard-coded here (this repo is public): it is an
  # env-var placeholder proxy-mcp expands at runtime (--expand-env) from the
  # sops-encrypted secrets/mcp-proxy-env, decrypted via EnvironmentFile (see
  # modules/home/mcp-services.nix). Unset → expands to "" → matches nothing →
  # fails closed, never accidentally exposes tools.
  kontainerRepo = "\${KONTAINER_REMOTE}";
  gateThroughProxy =
    name:
    let
      up = httpServices.${name};
    in
    {
      host = "127.0.0.1";
      port = proxiedPort;
      path = "/${name}/mcp";
      idleSec = 300;
      url = "http://${up.host}:${toString up.port}${up.path}";
      transportType = "streamable-http";
      mode = "perSession";
      repoWhitelist = [ kontainerRepo ];
    };
  proxied = {
    jenkins-mcp = gateThroughProxy "jenkins-mcp";
    sentry-mcp = gateThroughProxy "sentry-mcp";
  }
  // lib.optionalAttrs enableChrome {
    chrome-devtools = {
      host = "127.0.0.1";
      port = proxiedPort;
      path = "/chrome-devtools/mcp";
      idleSec = 300;
      command = "npx";
      args = [
        "-y"
        "chrome-devtools-mcp@1.5.0"
        "--autoConnect"
      ];
    };
  }
  // {
    # nix-mcp: stateless (queries live APIs), cwd-irrelevant → safe behind the
    # shared proxy. Moved off its own native-HTTP port (was 39101) to fold onto
    # the shared proxiedPort. Stdio mode = no --http flag; "shared" multiplexing
    # is harmless since it holds no per-session state. Route is /<attr>/mcp, so
    # the attr name stays `nix-mcp` (keeps mcp__nix-mcp__* tool names) → path
    # /nix-mcp/mcp.
    # ponytail: idleSec matches the DB servers; bump it if the NixOS option
    # index cold-reload after idle proves annoying.
    nix-mcp = {
      host = "127.0.0.1";
      port = proxiedPort;
      path = "/nix-mcp/mcp";
      idleSec = 300;
      command = nixMcp;
      args = [ ];
    };
    # ds-mcp: one unified readonly DB server (MySQL + MongoDB sources in one
    # config), replacing the separate mysql/mongodb entries. `serve` is the
    # stdio subcommand; `--read-only` force-readonlies every source on top of
    # the per-source readonly flag. Tools land under mcp__ds__* (query,
    # execute, schema, ping, list_sources).
    ds = {
      host = "127.0.0.1";
      port = proxiedPort;
      path = "/ds/mcp";
      idleSec = 300;
      command = dsMcp;
      args = [
        "serve"
        "--read-only"
        "--config"
        "${homeDir}/.config/ds-mcp/config.json"
      ];
    };
    # pty-mcp: real terminal (one-shot `run` + persistent PTY sessions +
    # sudo via askpass dialog). Stdio behind the shared proxy; "shared"
    # multiplexing is fine because sessions are keyed by session_id — all
    # windows just see one session table (pty_list lists them all), and the
    # server captures the user's login-shell env at startup so running under
    # systemd loses nothing. cwd-irrelevant (sessions take an explicit cwd,
    # default HOME). idleSec matches pty-mcp's own default session
    # idle-timeout (1800s): a shorter proxy clock would tear down the
    # backend — and every live ssh/vim/REPL session in it — that the server
    # itself still considers active. The explicit rofi askpass matches the
    # desktop launcher (autodetect only finds kdialog/zenity/ssh-askpass);
    # rofi reaches WAYLAND_DISPLAY via the systemd user-manager env, which
    # hyprland/niri import at session start.
    pty-mcp = {
      host = "127.0.0.1";
      port = proxiedPort;
      path = "/pty-mcp/mcp";
      idleSec = 1800;
      command = ptyMcp;
      args = [
        "--askpass"
        "rofi -dmenu -password -p sudo"
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
