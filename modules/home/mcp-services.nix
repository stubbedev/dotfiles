{ self, inputs, ... }:
{
  # Long-lived MCP servers run as shared systemd user services: each serves
  # streamable HTTP on a loopback port, started once at login. Opening N Claude
  # windows then costs no extra processes — every window is just an HTTP client
  # (setup-claude-code.nix wires the matching `type = "http"` entries), and the
  # heavy ones (nix-mcp's NixOS option index) load once for the whole session.
  #
  # Everything here is safe to share as ONE process because none depends on the
  # service's working directory: nix-mcp is stateless, and atlassian/jenkins/
  # sentry resolve the caller's repo from the per-session MCP *roots* each Claude
  # window reports over its own HTTP session. That per-session isolation is why
  # they are native HTTP rather than bridged through a stdio→HTTP proxy (which
  # would collapse all windows onto one upstream session and lose roots).
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
        };

        # The work servers shell out to `git` (repo detection from MCP roots), so
        # the service PATH must reach git; the server binaries themselves are
        # absolute store paths and need nothing.
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
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      in
      {
        systemd.user.services = lib.mapAttrs mkService servers.httpServices;

        # Restart on every `hm switch` so a changed server set / store path is
        # picked up even when sd-switch sees an identical unit (mirrors the
        # treemand pattern in modules/packages/treeman.nix).
        home.activation.restartMcpServices = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user try-restart ${
              lib.concatMapStringsSep " " (n: "${n}.service") (lib.attrNames servers.httpServices)
            } 2>/dev/null || true
          fi
        '';
      }
    );
}
