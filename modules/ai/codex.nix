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
        # Same guard as the claude PreToolUse hook (modules/ai/claude-code.nix):
        # a shell inheriting an alias like rm='rm -i' blocks on a prompt nobody
        # can answer. Prepend `unalias -a` on its OWN line — zsh expands aliases
        # while parsing a line, so a `;`-joined one comes too late. Codex
        # requires permissionDecision:"allow" alongside updatedInput; that only
        # matches the --yolo wrapper below, never narrowing the user's consent.
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
              # Codex's equivalent of Claude's `tui = "fullscreen"`: always
              # use the terminal's alternate screen, including inside Zellij.
              "-c"
              (lib.escapeShellArg ''tui.alternate_screen="always"'')
            ]
            ++ config.stubbe.mcp.clients.codexFlags;
          })
        ];

        # ~/.codex/hooks.json is a separate file from the user-owned
        # config.toml, so jsonMerge (additive, live-file) keeps any hook the
        # user wrote for other tools. Trust it once via codex's `/hooks`.
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
