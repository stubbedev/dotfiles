{
  pkgs,
  # Home directory, for building absolute --config paths in the work services.
  homeDir,
  # Absolute paths to the Go-built work-server binaries (flake inputs, passed by
  # both setup-claude-code.nix and mcp-proxy.nix). The throw defaults are lazy:
  # a consumer that never forces `httpServices.{atlassian,jenkins,sentry}-mcp`
  # need not supply them.
  jenkinsMcp ? throw "lib/mcp-servers.nix: jenkinsMcp store path required",
  sentryMcp ? throw "lib/mcp-servers.nix: sentryMcp store path required",
  atlassianMcp ? throw "lib/mcp-servers.nix: atlassianMcp store path required",
}:
let
  # Canonical MCP server definitions, split by how each is loaded into Claude
  # Code. Consumed by:
  #   modules/home/mcp-proxy.nix
  #     - `httpServices` → one systemd user service per entry (the server serves
  #       HTTP itself; `env`/`args` configure it).
  #     - `proxied`      → the mcp-proxy-go config (stdio→HTTP bridge).
  #   modules/activation/_non-privileged/setup-claude-code.nix
  #     - `httpServices` + `proxied` → global type:"http" client entries.
  #     - `global`       → top-level stdio entries.
  #
  # The split follows two axes — how a server learns the caller's repo, and how
  # its process is best shared:
  #
  # (zennotes used to be bridged here via a Go proxy; it was dropped from the
  # default set — `zen` is still installed, just not wired as an MCP server.)
  #
  #   httpServices  long-lived shared HTTP servers, one process each, started at
  #                 login. Every Claude window is just an HTTP client, so opening
  #                 N windows costs no extra process. Two kinds live here and
  #                 both are safe to share because they are NOT tied to the
  #                 process cwd:
  #                   • nix-mcp — stateless; cwd-irrelevant.
  #                   • atlassian/jenkins/sentry — cwd-sensitive in spirit, but
  #                     they now resolve the caller's repo from the per-session
  #                     MCP *roots* (the launch dir each Claude window reports
  #                     over its own HTTP session), not the server's cwd. So one
  #                     shared server serves every worktree correctly. This is
  #                     why they are NATIVE http (a direct per-window session): a
  #                     stdio→HTTP bridge would collapse all windows onto one
  #                     upstream session and lose per-session roots.
  #
  #   global        per-window stdio, loaded everywhere. srv/treeman are cheap
  #                 native binaries. chrome-devtools can't be shared (a daemon
  #                 would multiplex two windows onto one browser session) so it
  #                 stays per-window. Note: a stdio server's process spawns
  #                 eagerly at session start (`alwaysLoad:false` only defers the
  #                 tool schema, not the process), and MCP servers resolve only
  #                 at launch — no skill/hook can hot-add one — so per-window
  #                 stdio is the floor for these.
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
  };

  global = {
    chrome-devtools = {
      command = "npx";
      args = [
        "-y"
        "chrome-devtools-mcp@1.4.0"
        "--no-usage-statistics"
        "--auto-connect"
      ];
    };
    srv-mcp = {
      command = "srv";
      args = [ "mcp" ];
    };
    treeman-mcp = {
      command = "treeman";
      args = [ "mcp" ];
    };
  };
in
{
  inherit
    httpServices
    global
    ;
}
