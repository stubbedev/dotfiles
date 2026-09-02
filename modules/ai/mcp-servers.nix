# httpServices stay native HTTP rather than bridged: a stdio->HTTP bridge would
# collapse every window onto one upstream session, losing the per-request repo.
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
      # "perSession" is required: a "shared" session would collapse every window's
      # roots onto one upstream and break per-repo resolution. Reusing the
      # Placeholders, not literals: this repo is public. Unset expands to "" and
      # gates every client out, so a missing secret hides the tools rather than
      # exposing them everywhere.
      kontainerRepo = "\${KONTAINER_REMOTE}";
      kontainerCmsRepo = "\${KONTAINER_CMS_REMOTE}";
      kontainerSiteRepo = "\${KONTAINER_SITE_REMOTE}";
      kontainerHelpdeskRepo = "\${KONTAINER_HELPDESK_REMOTE}";
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
          repoWhitelist = [
            kontainerRepo
            kontainerCmsRepo
            kontainerSiteRepo
            kontainerHelpdeskRepo
          ];
          command = "npx";
          args = [
            "-y"
            "chrome-devtools-mcp@1.8.0"
            "--autoConnect"
            # One shared child (mode "shared") serves every window, so two
            # concurrent sessions would otherwise fight over the server's
            # implicitly-selected page. pageIdRouting makes pageId required on
            # page-scoped tools, so each session addresses its own tab.
            "--pageIdRouting"
            # Telemetry off: the Clearcut watchdog is a detached (setsid) ~180MB
            # node child that escapes group kills and orphans on every idle
            # teardown. No watchdog spawn at all with stats off.
            "--no-usage-statistics"
          ];
        };
      }
      // {
        nix-mcp = {
          host = "127.0.0.1";
          port = proxiedPort;
          path = "/nix-mcp/mcp";
          idleSec = 300;
          command = nixMcp;
          args = [ ];
          repoScoped = true;
        };
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
