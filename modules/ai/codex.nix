# Codex CLI, wired to the shared MCP inventory.
_: {
  flake.modules.homeManager.codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.codex (
      let
        # Same unalias guard as the claude PreToolUse hook. permissionDecision
        # must be "allow" with updatedInput; codex already runs --yolo.
        noAliasesHook = pkgs.writeShellScript "codex-hook-no-aliases" ''
          exec ${lib.getExe pkgs.jq} -c '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:(.tool_input+{command:("unalias -a 2>/dev/null\n"+.tool_input.command)})}}'
        '';
      in
      {
        home.packages = [
          (config.stubbe.gfx.bundle {
            pkg = pkgs.codex;
            gfx = false;
            # ~/.codex/config.toml remains user/`codex mcp add`-owned. Dotted
            # overrides add the canonical managed inventory without replacing
            # unrelated user-defined servers.
            flags = [
              "--yolo"
              "--dangerously-bypass-hook-trust"
              # Codex's equivalent of Claude's `tui = "fullscreen"`: always
              # use the terminal's alternate screen, including inside Zellij.
              "-c"
              (lib.escapeShellArg ''tui.alternate_screen="always"'')
            ]
            ++ config.stubbe.mcp.clients.codexFlags;
          })
        ];

        # hooks.json is separate from the user-owned config.toml; trust it via codex `/hooks`.
        stubbe.setup.codex.script = ''
          ${pkgs.stubbe.jsonMerge {
            name = "codex-hooks-no-aliases";
            target = "${config.home.homeDirectory}/.codex/hooks.json";
            patch = {
              hooks.PreToolUse = [
                {
                  matcher = "^Bash$";
                  hooks = [
                    {
                      type = "command";
                      command = "${noAliasesHook}";
                      timeout = 30;
                      statusMessage = "Clearing shell aliases";
                    }
                  ];
                }
              ];
            };
          }}
        '';
      }
    );
}
