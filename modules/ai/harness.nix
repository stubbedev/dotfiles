# Harness is the stubbedev fork of Crush (github:stubbedev/harness). Everything
# this module used to patch into the Go source -- the Catppuccin palette, the
# git status header, the hidden reasoning blocks, the one-row prompt floor, the
# suppressed update toast -- is a config option in the fork, so the package is
# taken as-is and the whole postPatch block is gone.
#
# The config file can be a read-only store symlink: every write Harness makes
# itself (model selection, onboarding, docker MCP) goes to ScopeGlobal, which is
# ~/.local/share/harness/state.yaml -- a different file, and one loaded AFTER
# this one, so an in-app model switch still wins over the `models` block here.
{ inputs, ... }:
{
  flake.modules.homeManager.harness =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.harness (
      let
        inherit (pkgs.stdenv.hostPlatform) system;
        harness = inputs.harness.packages.${system}.harness;
      in
      {
        home.packages = [ harness ];

        sops.secrets.z-ai-token = pkgs.stubbe.secret { name = "z-ai-token"; };

        # YAML, not JSON: the fork reads $XDG_CONFIG_HOME/harness/config.yaml
        # (hand-written, never written back to) and keeps its own writes in
        # $XDG_DATA_HOME/harness/state.yaml.
        xdg.configFile."harness/config.yaml".source = pkgs.stubbe.gen.yaml "harness-config.yaml" {
          # Only the credential is ours: catwalk's built-in `zai` provider
          # carries the endpoint and the model list, and a user entry under the
          # same id overrides field by field instead of replacing it. The token
          # stays out of the world-readable store because Harness expands config
          # values through its embedded shell, so $(...) runs at load time.
          providers.zai.api_key = "$(cat ${config.sops.secrets.z-ai-token.path})";

          # The pair to start from on a machine with no state yet. The state
          # file is loaded after this one, so switching model in-app still
          # sticks; this only decides what a fresh checkout opens with.
          models = {
            large = {
              provider = "zai";
              model = "glm-5.3";
              reasoning_effort = "xhigh";
              max_tokens = 131072;
            };
            # The small model runs titles, summaries and the cheap internal
            # calls, so it gets the flash sibling: same 1M context and 131072
            # output cap, a fraction of the cost.
            small = {
              provider = "zai";
              model = "glm-5.3-flash";
              reasoning_effort = "xhigh";
              max_tokens = 131072;
            };
          };

          mcp = config.stubbe.mcp.clients.harness;

          # The same language server inventory Claude Code's LSP plugin ships,
          # in Harness's dialect: `filetypes` entries match as ".<ext>" suffixes
          # and server settings live under `options`/`init_options`. The
          # commands are store paths, which Harness needs: user-configured
          # servers skip its PATH probe, and it runs without nvim's wrapper PATH
          # to find the binaries by name.
          lsp = config.stubbe.lsp.clients.harness;

          # `harness --yolo` is a flag on the ROOT command only, so baking it
          # into a wrapper would make `harness run`/`harness logs` die with
          # "unknown flag". allowed_tools is the config-level equivalent and
          # applies to both the TUI and `harness run`. MCP tool calls never
          # reach the permission service at all, so this list only needs
          # Harness's own tools -- mirrored from allToolNames() in
          # internal/config/config.go. A tool added upstream after this list
          # simply prompts once.
          permissions.allowed_tools = [
            "agent"
            "bash"
            "harness_info"
            "harness_logs"
            "job_output"
            "job_kill"
            "download"
            "edit"
            "multiedit"
            "lsp_diagnostics"
            "lsp_references"
            "lsp_restart"
            "lsp_symbols"
            "lsp_definition"
            "lsp_call_hierarchy"
            "lsp_rename"
            "lsp_replace_symbol"
            "fetch"
            "agentic_fetch"
            "glob"
            "grep"
            "ls"
            "question"
            "sourcegraph"
            "todos"
            "view"
            "write"
            "list_mcp_resources"
            "read_mcp_resource"
          ];

          options = {
            tui = {
              # The palette that used to be a generated catppuccin.go dropped
              # into internal/ui/styles: same role mapping, same hex values as
              # modules/core/lib/palette.nix, now a built-in theme the config
              # picks by name.
              theme = "catppuccin-mocha";
              # The sidebar is nearly all of the chrome -- session title, cwd,
              # model card, changed-file list, LSP/MCP/skills panels -- and
              # compact_mode is what drops it. Below 120 columns it is forced on
              # anyway, so the wide layout was never the default.
              compact_mode = true;
              # Split view spends half the width on the pre-image; unified reads
              # like `git diff` and survives a narrow window.
              diff_mode = "unified";
              scrollbar = "never";
              # Leaves view.BackgroundColor unset, so the terminal's own
              # background (and its opacity) shows through instead of bgBase
              # being painted over the whole screen. Widget backgrounds still
              # paint, but they are the same Catppuccin surfaces the terminal
              # uses, so the seams do not show.
              transparent = true;
              # Prints nothing on quit: no ASCII-art logo, no thanks, no resume
              # hint. `compact` would keep only the resume line.
              exit_banner = "none";
              # Branch, working-tree counts and ahead/behind in the compact
              # header, starship-style -- the status bar cship gives Claude
              # Code. Was a generated gitinfo.go plus two header.go rewrites.
              git_status = true;
              # Reasoning is still requested, streamed and stored; only the
              # transcript block is suppressed. Was two assistant.go /
              # messages.go substitutions.
              show_thinking = false;
              # 3 rows was only the floor: the textarea is DynamicHeight and
              # grows to fit either way, so 1 just starts it collapsed.
              textarea_min_height = 1;
            };

            disable_metrics = true;
            # The version follows this flake input, so an update toast has
            # nothing actionable behind it.
            disable_update_check = true;

            # Matches includeCoAuthoredBy = false for Claude Code: no trailer,
            # no "Generated with" line in commits or PR bodies.
            attribution = {
              trailer_style = "none";
              generated_with = false;
            };
          };
        };
      }
    );
}
