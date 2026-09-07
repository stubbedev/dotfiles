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
        (pkgs.stubbe.headroomWrap {
          tool = "codex";
          pkg = pkgs.codex;
          flags = [
            "--no-mcp"
            "--code-memory"
            "none"
          ];
          toolFlags = [
            "--yolo"
            "--dangerously-bypass-hook-trust"
            "-c"
            (lib.escapeShellArg ''tui.alternate_screen="always"'')
          ]
          ++ config.stubbe.mcp.clients.codexFlags;
        })
      ];

      stubbe.setup.codex.script = ''
        ${pkgs.stubbe.setup.jsonMerge {
          name = "codex-hooks";
          target = "${config.home.homeDirectory}/.codex/hooks.json";
          patch = {
            # Alias guard lives in zsh: modules/shell.nix sets no_aliases for
            # non-interactive shells. Empty list prunes the old hook.
            hooks.PreToolUse = [ ];
          };
        }}
      '';
    };
}
