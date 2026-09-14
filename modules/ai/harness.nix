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
        sops.secrets.opencode-api-token = pkgs.stubbe.secret { name = "opencode-api-token"; };
        sops.secrets.meta-muse-spark-api-token = pkgs.stubbe.secret {
          name = "meta-muse-spark-api-token";
        };
        sops.secrets.openai-token = pkgs.stubbe.secret { name = "openai-token"; };

        # YAML, not JSON: the fork reads $XDG_CONFIG_HOME/harness/config.yaml
        # (hand-written, never written back to) and keeps its own writes in
        # $XDG_DATA_HOME/harness/state.yaml.
        xdg.configFile."harness/config.yaml".source = pkgs.stubbe.gen.yaml "harness-config.yaml" {
          # Only the credentials are ours: the models.dev catalogue carries
          # the endpoints and the model lists, and a user entry under the same
          # id overrides field by field instead of replacing it. The tokens
          # stay out of the world-readable store because Harness expands config
          # values through its embedded shell, so $(...) runs at load time.
          #
          # The ids are models.dev's, which are not catwalk's: the GLM coding
          # subscription is "zai-coding-plan" (api.z.ai/api/coding/paas/v4),
          # while plain "zai" is the pay-per-token API on the same host and
          # answers a subscription token with 429 "Insufficient balance".
          providers = {
            "zai-coding-plan".api_key = "$(cat ${config.sops.secrets.z-ai-token.path})";

            # One OpenCode token authorises both of its gateways: opencode is
            # the full pay-per-token catalogue (zen), opencode-go the
            # flat-rate coding plan riding the same account.
            opencode.api_key = "$(cat ${config.sops.secrets.opencode-api-token.path})";
            "opencode-go".api_key = "$(cat ${config.sops.secrets.opencode-api-token.path})";

            # Plain platform.openai.com key: models.dev already carries the
            # endpoint and the model list under the "openai" id, so the
            # credential is the only thing missing.
            openai.api_key = "$(cat ${config.sops.secrets.openai-token.path})";

            # Meta's Model API (dev.meta.ai) has no models.dev entry, so this one
            # is spelled out in full: OpenAI-compatible chat completions behind
            # the documented base URL, and the muse-spark line listed by hand
            # because there is no registry to inherit limits from. Every
            # variant: 1M context, 128k output, reasoning, tool calls, and
            # text/image/video/audio/PDF input. Only the -contributor SKUs are
            # listed -- same checkpoint on the same key, ~12x cheaper
            # ($0.10/$0.20 vs $1.25/$4.25 per M) in exchange for Meta training
            # on the traffic and a 60 req/min ceiling instead of the standard
            # tier's 3000, which is fine for solo sessions. There is no
            # 1.1-contributor.
            meta = {
              type = "openai-compat";
              base_url = "https://api.meta.ai/v1";
              api_key = "$(cat ${config.sops.secrets.meta-muse-spark-api-token.path})";
              models =
                map
                  (v: {
                    id = "muse-spark-${v}";
                    name = "Muse Spark ${v}";
                    context_window = 1048576;
                    default_max_tokens = 131072;
                    can_reason = true;
                    supports_attachments = true;
                  })
                  [
                    "1.3-contributor"
                    "1.2-contributor"
                  ];
            };
          };

          # The pair to start from on a machine with no state yet. The state
          # file is loaded after this one, so switching model in-app still
          # sticks; this only decides what a fresh checkout opens with.
          models = {
            large = {
              provider = "zai-coding-plan";
              model = "glm-5.3";
              reasoning_effort = "max";
              max_tokens = 131072;
            };
            # The small model runs titles, summaries and the cheap internal
            # calls, so it gets the flash sibling: same 1M context and 131072
            # output cap, a fraction of the cost.
            small = {
              provider = "zai-coding-plan";
              model = "glm-5.3-flash";
              reasoning_effort = "max";
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
