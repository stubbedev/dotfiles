# Codex CLI, wired to the shared MCP inventory.
_: {
  flake.modules.homeManager.codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.codex {
      home.packages = [
        (config.stubbe.gfx.bundle {
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
          ++ config.stubbe.mcp.clients.codexFlags;
        })
      ];
    };
}
