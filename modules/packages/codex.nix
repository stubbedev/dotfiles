{ self, inputs, ... }:
{
  flake.modules.homeManager.packagesCodex =
    {
      pkgs,
      lib,
      config,
      homeLib,
      ...
    }:
    lib.mkIf config.features.codex (
      let
        servers = import (self + "/lib/mcp-servers-wired.nix") {
          inherit
            self
            inputs
            pkgs
            config
            ;
        };
        mcpClients = import (self + "/lib/mcp-client-configs.nix") {
          inherit lib servers;
        };
      in
      {
        home.packages = [
          (homeLib.mkWrappedPackage {
            pkg = pkgs.codex;
            gfx = false;
            # ~/.codex/config.toml remains user/`codex mcp add`-owned. Dotted
            # overrides add the canonical managed inventory without replacing
            # unrelated user-defined servers.
            flags = [
              "--yolo"
              # Codex's equivalent of Claude's `tui = "fullscreen"`: always
              # use the terminal's alternate screen, including inside Zellij.
              "-c"
              (lib.escapeShellArg ''tui.alternate_screen="always"'')
            ]
            ++ mcpClients.codexFlags;
          })
        ];
      }
    );
}
