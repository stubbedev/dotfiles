# Resolves flake-input store paths + feature gates, then imports the canonical
# server definitions (lib/mcp-servers.nix). Every consumer calls this so the
# binary wiring lives in ONE place. lib/mcp-client-configs.nix projects the
# result 1:1 into Claude and Codex; mcp-services.nix builds the shared services.
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
  nixMcp = "${inputs."nix-mcp".packages.${system}.default}/bin/nix-mcp";
  dsMcp = "${inputs."ds-mcp".packages.${system}.default}/bin/ds-mcp";
  ptyMcp = "${inputs."pty-mcp".packages.${system}.default}/bin/pty-mcp";
  notmuchMcp = "${inputs."notmuch-mcp".packages.${system}.default}/bin/notmuch-mcp";
  # Feature gates (mirror modules/features.nix): a false gate drops the entry
  # and never forces its *Mcp store path.
  enableChrome = config.features.browsers;
  # notmuch-mcp needs the `notmuch` binary + mail wiring, both desktop-only
  # (modules/packages/cli/mail.nix, modules/files/mail.nix).
  enableMail = config.features.desktop;
}
