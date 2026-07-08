# Resolves flake-input store paths + feature gates, then imports the canonical
# server definitions (lib/mcp-servers.nix). Both consumers call this so the
# binary wiring lives in ONE place — add/rename a server once, not twice:
#   modules/activation/_non-privileged/setup-claude-code.nix  (client entries)
#   modules/home/mcp-services.nix                              (systemd units)
{
  self,
  inputs,
  pkgs,
  config,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
import (self + "/lib/mcp-servers.nix") {
  inherit pkgs;
  homeDir = config.home.homeDirectory;
  # Go-built servers from flake inputs → offline store-path spawn.
  jenkinsMcp = "${inputs."jenkins-mcp".packages.${system}.default}/bin/jenkins-mcp";
  sentryMcp = "${inputs."sentry-mcp".packages.${system}.default}/bin/sentry-mcp";
  atlassianMcp = "${inputs."atlassian-mcp".packages.${system}.default}/bin/atlassian-mcp";
  srvMcp = "${inputs.srv.packages.${system}.srv}/bin/srv";
  treemanMcp = "${inputs.treeman.packages.${system}.treeman}/bin/treeman";
  nixMcp = "${inputs."nix-mcp".packages.${system}.default}/bin/nix-mcp";
  dsMcp = "${inputs."ds-mcp".packages.${system}.default}/bin/ds-mcp";
  ptyMcp = "${inputs."pty-mcp".packages.${system}.default}/bin/pty-mcp";
  # Feature gates (mirror modules/features.nix): a false gate drops the entry
  # and never forces its *Mcp store path.
  enableSrv = config.features.srv;
  enableTreeman = config.features.treeman;
  enableChrome = config.features.browsers;
}
