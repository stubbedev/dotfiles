# The canonical MCP server inventory, published as `config.stubbe.mcp.servers`
# for modules/ai/mcp-services.nix (systemd units) and modules/ai/mcp-clients.nix
# (per-agent renderings).
#
# `httpServices` are long-lived shared HTTP servers started at login. They stay
# native HTTP rather than being bridged: a stdio->HTTP bridge collapses every
# window onto one upstream session, and these resolve the caller's repo from the
# per-request X-Repo-Root header. (Per-session MCP roots is the older path to the
# same value; MCP 2026-07-28 bans the server->client call it needs, so the header
# is now the mechanism and roots only a fallback.)
#
# `proxied` are stdio servers fronted by ONE socket-activated proxy-mcp, each
# served at /<name>/mcp on `proxiedPort`. Backends connect lazily and retire
# after their own `idleSec`, so the heavy browser drops while a DB stays warm.
#
# `repoScoped` opts an entry OUT of the global client inventory: the unit and the
# proxy route are built as usual, but no agent loads it everywhere. This repo
# names those in .mcp.json (Claude), opencode.jsonc (opencode) and
# .codex/config.toml (Codex).
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

      # Store paths, so a spawn never makes an `npx @latest` round-trip.
      flakeBin = input: bin: "${inputs.${input}.packages.${system}.default}/bin/${bin}";
      jenkinsMcp = flakeBin "jenkins-mcp" "jenkins-mcp";
      sentryMcp = flakeBin "sentry-mcp" "sentry-mcp";
      atlassianMcp = flakeBin "atlassian-mcp" "atlassian-mcp";
      nixMcp = flakeBin "nix-mcp" "nix-mcp";
      dsMcp = flakeBin "ds-mcp" "ds-mcp";
      ptyMcp = flakeBin "pty-mcp" "pty-mcp";
      notmuchMcp = flakeBin "notmuch-mcp" "notmuch-mcp";

      enableChrome = config.features.browsers;
      enableMail = config.features.desktop;
      mkHttpServer =
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
        atlassian-mcp = mkHttpServer {
          exe = atlassianMcp;
          port = 39102;
          name = "atlassian-mcp";
        };
        jenkins-mcp = mkHttpServer {
          exe = jenkinsMcp;
          port = 39103;
          name = "jenkins-mcp";
        };
        sentry-mcp = mkHttpServer {
          exe = sentryMcp;
          port = 39104;
          name = "sentry-mcp";
        };
      };
      # 39107/39108 are retired (srv-mcp / treeman-mcp). Do not reuse them without
      # checking for a stale unit on an un-switched host.

      proxiedPort = 39105;
      # atlassian is gated by HOST (every repo on the forge has Jira context worth
      # reaching); jenkins/sentry to the ONE repo they are configured against.
      # "perSession" is required: a "shared" session would collapse every window's
      # roots onto one upstream and break per-repo resolution. Reusing the
      # httpServices attr key makes the gated proxy route win the client entry.
      #
      # Placeholders, not literals: this repo is public. Unset expands to "" and
      # gates every client out, so a missing secret hides the tools rather than
      # exposing them everywhere.
      kontainerRepo = "\${KONTAINER_REMOTE}";
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
        # ponytail: bump idleSec if the NixOS option index cold-reload after idle
        # proves annoying.
        nix-mcp = {
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/nix-mcp/mcp";
          idleSec = 300;
          command = nixMcp;
          args = [ ];
          repoScoped = true;
        };
        # A source with an `ssh` block holds a tunnel open for the life of the
        # backend, so idle-exit here is what stops the staging tunnel living 24/7.
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
        # idleSec matches pty-mcp's own session idle-timeout: a shorter proxy
        # clock would tear down live ssh/vim/REPL sessions the server still
        # considers active. Askpass is explicit because autodetect only finds
        # kdialog/zenity/ssh-askpass.
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
      # No env needed: notmuch falls back to the legacy ~/.notmuch-config that
      # modules/mail.nix writes, and the binary comes off the proxy service PATH.
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

    in
    {
      options.stubbe.mcp.servers = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "MCP server inventory, split by how each is hosted: httpServices and proxied.";
      };

      config.stubbe.mcp.servers = {
        inherit httpServices proxied;
      };
    };
}
