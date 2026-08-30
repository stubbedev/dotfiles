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
            flags = [
              "--yolo"
              "--dangerously-bypass-hook-trust"
              "-c"
              (lib.escapeShellArg ''tui.alternate_screen="always"'')
            ]
            ++ config.stubbe.mcp.clients.codexFlags;
          })
        ];

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
