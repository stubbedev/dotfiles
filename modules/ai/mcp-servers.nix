# The canonical MCP server inventory, published as `config.stubbe.mcp.servers`
# so every agent (Claude Code, Codex, Crush) and the systemd units in
# modules/ai/mcp-services.nix read ONE definition instead of each importing a
# library and re-resolving the binaries.
{ inputs, ... }:
{
  flake.modules.homeManager.mcpServers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      inherit (config.home) homeDirectory;

      # Go/Rust servers from flake inputs, so each spawns as an offline store
      # path rather than an `npx …@latest` round-trip.
      exe = input: bin: "${inputs.${input}.packages.${system}.default}/bin/${bin}";
      jenkinsMcp = exe "jenkins-mcp" "jenkins-mcp";
      sentryMcp = exe "sentry-mcp" "sentry-mcp";
      atlassianMcp = exe "atlassian-mcp" "atlassian-mcp";
      nixMcp = exe "nix-mcp" "nix-mcp";
      dsMcp = exe "ds-mcp" "ds-mcp";
      ptyMcp = exe "pty-mcp" "pty-mcp";
      notmuchMcp = exe "notmuch-mcp" "notmuch-mcp";

      # Per-feature gates. A server is wired only when its backing tool or
      # daemon is actually installed — otherwise we would start a unit and
      # advertise a client entry for a binary whose state is absent.
      # chrome-devtools drives the user's real Chrome over CDP; notmuch-mcp
      # shells out to `notmuch` and reads the maildir modules/mail.nix wires.
      enableChrome = config.features.browsers;
      enableMail = config.features.desktop;
      # Canonical MCP server definitions, split by how each is hosted. Consumed by:
      #   modules/ai/mcp-services.nix
      #     - `httpServices` → one systemd user service per entry (the server serves
      #       HTTP itself; `env`/`args` configure it), started at login.
      #     - `proxied`      → a .socket + a socket-activated proxy-mcp service per
      #       entry (stdio→streamable-HTTP bridge), started on demand.
      #   modules/ai/mcp-clients.nix
      #     - `httpServices` + `proxied` → shared HTTP entries for Claude/Codex.
      #     - `global`       → top-level stdio entries for Claude/Codex.
      #
      # The split follows two axes — how a server learns the caller's repo, and how
      # its process is best shared:
      #
      #
      #   httpServices  long-lived shared HTTP servers, one process each, started at
      #                 login. Every agent window is just an HTTP client, so opening
      #                 N windows costs no extra process. All are safe to share as
      #                 one process because they are NOT tied to the process cwd:
      #                 atlassian/jenkins/sentry are cwd-sensitive in
      #                     spirit, but they resolve the caller's repo/worktree from
      #                     the X-Repo-Root header each window sends (set to that
      #                     window's launch dir via the shared client config), not the
      #                     server's cwd. So one shared server serves every worktree
      #                     correctly. Per-session MCP *roots* is the older path to
      #                     the same value and still works, but MCP 2026-07-28
      #                     (SEP-2322/2575) bans the server→client call it needs, so
      #                     the header — which outranks roots in every server — is
      #                     now the mechanism and roots is only the fallback for
      #                     clients that don't send it. This is still why they are
      #                     NATIVE http (a direct per-window session): a stdio→HTTP
      #                     bridge would collapse all windows onto one upstream
      #                     session and lose per-session roots.
      #
      #   proxied       shared stdio servers fronted by ONE proxy-mcp
      #                 (stdio→streamable-HTTP) and started ON DEMAND via systemd
      #                 socket activation. chrome-devtools lives here: we want
      #                 exactly ONE browser, so every agent window is an HTTP client
      #                 of one proxy-mcp that owns one `npx chrome-devtools-mcp` stdio
      #                 child (mode "shared": proxy-mcp multiplexes every window onto
      #                 one upstream session, so one browser). The accepted tradeoff
      #                 vs. the old per-window model: windows share one browser
      #                 session rather than each driving their own. modules/ai/
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
      #   global        per-window stdio, loaded everywhere. Currently empty. Note: a stdio server's process spawns
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
      # modules/ai/mcp-services.nix from the sops blob in secrets/<name>-mcp).
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
            "${homeDirectory}/.config/${name}/config.json"
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
      };
      # NOTE: 39107/39108 are retired (srv-mcp / treeman-mcp). Their CLIs and state
      # daemons stay — only the MCP fronts are gone: their tools duplicated what the
      # shell already does well, at the cost of two always-on units. Don't reuse the
      # ports without checking for a stale unit on an un-switched host.

      # Shared stdio servers fronted by ONE socket-activated proxy-mcp. Every entry
      # is served by the same proxy process on the same `proxiedPort`, distinguished
      # by `path` (/<name>/mcp); mcp-services.nix aggregates them into one config.
      #   host/port   the single shared loopback addr the one .socket listens on and
      #               every agent HTTP client connects to. proxy-mcp adopts the
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
      #   repoScoped  opt OUT of the global client inventory: the systemd unit and
      #               the proxy route are built exactly as usual, but
      #               modules/ai/mcp-clients.nix drops the entry, so no agent loads
      #               it everywhere. A repo that wants it names the URL below in its
      #               own .mcp.json. For servers whose tools are noise in most repos
      #               (nix-mcp outside a Nix repo, pty-mcp outside one you trust with
      #               a real terminal) — see that file for the exact JSON.
      # chrome-devtools gated on enableChrome (features.browsers): it drives the
      # user's real Chrome over CDP, useless on a host with no browser installed.
      # It is ALSO repo-gated (repoWhitelist, see its entry below) to the three web
      # apps it is ever pointed at.
      # --autoConnect attaches to the already-running stable-channel Chrome instead
      # of launching its own (Chrome 144+; remote debugging must be enabled once in
      # chrome://inspect/#remote-debugging).
      #
      # ds-mcp (one readonly DB server for MySQL + MongoDB sources) joins the SAME
      # proxy (repo-gated too — see its entry). proxied (not httpServices) is the right home precisely
      # because of idle-exit — a source with an `ssh` block holds an SSH tunnel
      # open for the life of the backend, so a login-time httpService would keep
      # the staging tunnel up 24/7; here the tunnel (and the backend) die idleSec
      # after the last query and re-establish on the next, while leaving the
      # browser backend alone. mode "shared" multiplexes every window onto one
      # upstream session, which is fine: each tool call is an independent query, no
      # per-session state to collapse. `--read-only` force-readonlies every source
      # on top of the per-source flag. Config decrypts from sops
      # (modules/ai/mcp-services.nix) to ~/.config/ds-mcp/config.json.
      proxiedPort = 39105;
      # atlassian/jenkins/sentry are repo-gated: only an agent window whose workspace
      # git remote matches sees their tools. atlassian is gated by HOST — every repo
      # on the company forge has Jira/Bitbucket context worth reaching — while
      # jenkins/sentry are gated to the ONE repo they are configured against. proxy-mcp's per-backend repoWhitelist
      # does the gating (matched against the client's remotes, normalized across
      # ssh/https and a trailing .git; fails closed for a client exposing no
      # workspace). They keep their native HTTP systemd units as the UPSTREAM — the
      # proxy just fronts them as url-backends in `mode "perSession"` so each
      # window's MCP roots are relayed to a dedicated upstream session (a "shared"
      # session would collapse every window's roots onto one upstream, breaking
      # per-repo resolution). The proxied entry reuses the same attr key as its
      # httpServices twin, so the client projection's merge makes the gated proxy
      # route WIN the client entry (the direct :391xx entry is overridden away).
      #
      # Neither the remote nor the forge hostname is hard-coded here (this repo is
      # public): both are env-var placeholders proxy-mcp expands at runtime
      # (--expand-env) from the sops-encrypted secrets/mcp-proxy-env, decrypted via
      # EnvironmentFile (see modules/ai/mcp-services.nix). Unset → expands to ""
      # → no entry resolves → proxy-mcp >= 0.0.22 gates every client out, so a
      # missing secret hides the tools rather than exposing them everywhere.
      kontainerRepo = "\${KONTAINER_REMOTE}";
      # The two other frontend/app repos worth driving a browser against. Same
      # placeholder scheme (values live in secrets/mcp-proxy-env), same fail-closed
      # behaviour when unset.
      kontainerCmsRepo = "\${KONTAINER_CMS_REMOTE}";
      kontainerSiteRepo = "\${KONTAINER_SITE_REMOTE}";
      # A whitelist entry with no path component gates a whole git host: every repo
      # cloned from it matches, across ssh/https and regardless of port (proxy-mcp
      # >= 0.0.21). Set KONFORM_HOST to the bare hostname — a value WITH a path
      # would silently narrow this to one repo instead.
      konformHost = "\${KONFORM_HOST}";
      gateThroughProxy =
        name: repoWhitelist:
        let
          up = httpServices.${name};
        in
        {
          inherit repoWhitelist;
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/${name}/mcp";
          idleSec = 300;
          url = "http://${up.host}:${toString up.port}${up.path}";
          transportType = "streamable-http";
          mode = "perSession";
        };
      proxied = {
        atlassian-mcp = gateThroughProxy "atlassian-mcp" [ konformHost ];
        jenkins-mcp = gateThroughProxy "jenkins-mcp" [ kontainerRepo ];
        sentry-mcp = gateThroughProxy "sentry-mcp" [ kontainerRepo ];
      }
      // lib.optionalAttrs enableChrome {
        chrome-devtools = {
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/chrome-devtools/mcp";
          idleSec = 300;
          # Repo-gated like ds/jenkins/sentry: browser automation is only ever
          # aimed at the three web apps, and everywhere else its 30-odd tools are
          # pure schema noise. Gating is per DOWNSTREAM session (from the client's
          # X-Repo-Root), so the one shared browser upstream is unaffected.
          repoWhitelist = [
            kontainerRepo
            kontainerCmsRepo
            kontainerSiteRepo
          ];
          command = "npx";
          args = [
            "-y"
            "chrome-devtools-mcp@1.5.0"
            "--autoConnect"
            # Telemetry off: the Clearcut watchdog is a detached (setsid) ~180MB
            # node child that escapes group kills and orphans on every idle
            # teardown. No watchdog spawn at all with stats off.
            "--no-usage-statistics"
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
          repoScoped = true;
        };
        # ds-mcp: one unified readonly DB server (MySQL + MongoDB sources in one
        # config), replacing the separate mysql/mongodb entries. `serve` is the
        # stdio subcommand; `--read-only` force-readonlies every source on top of
        # the per-source readonly flag. Tools land under mcp__ds__* (query,
        # execute, schema, ping, list_sources).
        # repoWhitelist: the only databases configured are the Kontainer ones, so
        # the tools are noise (and a footgun) in any other repo. mode stays "shared"
        # — gating is evaluated per DOWNSTREAM session from its X-Repo-Root, so it
        # works regardless of how the upstream is multiplexed.
        ds = {
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/ds/mcp";
          idleSec = 300;
          repoWhitelist = [ kontainerRepo ];
          command = dsMcp;
          args = [
            "serve"
            "--read-only"
            "--config"
            "${homeDirectory}/.config/ds-mcp/config.json"
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
        # hyprland import at session start.
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
          repoScoped = true;
        };
      }
      # notmuch-mcp: search/read/tag the local notmuch mail index. Stdio behind the
      # shared proxy — "shared" multiplexing is fine (each tool call is an
      # independent notmuch invocation, no per-session state) and cwd-irrelevant
      # (queries name the mail store, not the repo). Gated on enableMail
      # (features.desktop): it shells out to `notmuch`, which only lands in
      # home.packages on a desktop host (modules/mail.nix), and reads
      # the maildir/index that modules/mail.nix wires there.
      #
      # No env: notmuch falls back to the legacy ~/.notmuch-config, which mail.nix
      # writes, when no XDG config exists — so the NOTMUCH_CONFIG sessionVariable
      # (a shell-profile value the systemd user service never sees) is not needed.
      # The `notmuch` binary comes off the proxy service's profileDirectory PATH.
      # Attachments are written to ~/.cache/notmuch-mcp/attachments, never piped
      # through the conversation.
      // lib.optionalAttrs enableMail {
        notmuch-mcp = {
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/notmuch-mcp/mcp";
          idleSec = 300;
          command = notmuchMcp;
          args = [ ];
        };
      };

      # Per-window stdio servers, loaded everywhere. Empty since srv/treeman became
      # shared HTTP daemons and the DB servers moved to `proxied`; kept as an
      # explicit category so a future stdio-only server has an obvious home (and
      # modules/ai/mcp-clients.nix still maps it).
      global = { };
    in
    {
      options.stubbe.mcp.servers = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "MCP server inventory, split by how each is hosted: httpServices, proxied, global.";
      };

      config.stubbe.mcp.servers = {
        inherit httpServices proxied global;
      };
    };
}
