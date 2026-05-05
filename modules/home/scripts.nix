_: {
  flake.modules.homeManager.scripts =
    {
      config,
      lib,
      homeLib,
      constants,
      ...
    }:
    let
      # Standalone scripts that aren't tied to a specific app's config dir.
      # Built as Nix bins so they live under ~/.nix-profile/bin/ on PATH.
      # Other modules reference paths via `${scripts.<name>}/bin/<name>` —
      # systemd ExecStart, polkit-allowed targets, etc.
      #
      # Naming convention: <namespace>-<action>.
      #   mail-*    aerc/email helpers
      #   monitor-* display brightness / monitor controls
      #   tmux-*    tmux launcher wrappers
      #   fzf-*     fzf-driven pickers (return strings; tmux-pick-* wrap them)
      #   stb       personal CLI
      scripts = {
        mail-open = homeLib.mkScriptBin {
          name = "mail-open";
          source = "src/_shared/scripts/open-mail";
          vars.TERM = constants.paths.term;
        };
        mail-unsubscribe = homeLib.mkScriptBin {
          name = "mail-unsubscribe";
          source = "src/aerc/scripts/unsubscribe";
        };
        mail-pager = homeLib.mkScriptBin {
          name = "mail-pager";
          source = "src/aerc/scripts/nvim-pager.sh";
        };
        monitor-brightness = homeLib.mkScriptBin {
          name = "monitor-brightness";
          source = "src/_shared/scripts/monitor.brightness.sh";
        };
        waybar-launch = homeLib.mkScriptBin {
          name = "waybar-launch";
          source = "src/_shared/scripts/waybar.launch.sh";
        };
        power-profile-fix = homeLib.mkScriptBin {
          name = "power-profile-fix";
          source = "src/_shared/scripts/power.profile.fix.sh";
        };

        # Personal CLI + tmux launchers + fzf pickers (formerly under bin/).
        # stb-install stays in bin/ because it bootstraps Nix itself.
        stb = homeLib.mkScriptBin {
          name = "stb";
          source = "bin/stb";
        };

        tmux-claude = homeLib.mkScriptBin {
          name = "tmux-claude";
          source = "bin/tmux-claude";
        };
        tmux-lazy-docker = homeLib.mkScriptBin {
          name = "tmux-lazy-docker";
          source = "bin/tmux-lazy-docker";
        };
        tmux-lazy-git = homeLib.mkScriptBin {
          name = "tmux-lazy-git";
          source = "bin/tmux-lazy-git";
        };
        tmux-new-session = homeLib.mkScriptBin {
          name = "tmux-new-session";
          source = "bin/tmux-new-session";
        };
        tmux-opencode = homeLib.mkScriptBin {
          name = "tmux-opencode";
          source = "bin/tmux-opencode";
        };
        tmux-system-monitor = homeLib.mkScriptBin {
          name = "tmux-system-monitor";
          source = "bin/tmux-system-monitor";
        };

        # tmux-pick-* are interactive: they let fzf select a target, then
        # spawn / attach a tmux session there. fzf-pick-* are the headless
        # pickers (just emit the chosen path) that the tmux-pick-* and
        # zsh functions consume.
        tmux-pick-session = homeLib.mkScriptBin {
          name = "tmux-pick-session";
          source = "bin/tmux-pick-session";
        };
        tmux-pick-project = homeLib.mkScriptBin {
          name = "tmux-pick-project";
          source = "bin/tmux-pick-project";
        };
        tmux-pick-directory = homeLib.mkScriptBin {
          name = "tmux-pick-directory";
          source = "bin/tmux-pick-directory";
        };
        fzf-pick-project = homeLib.mkScriptBin {
          name = "fzf-pick-project";
          source = "bin/fzf-pick-project";
        };
        fzf-pick-directory = homeLib.mkScriptBin {
          name = "fzf-pick-directory";
          source = "bin/fzf-pick-directory";
        };
      };
    in
    {
      _module.args.scripts = scripts;
      home.packages = lib.mkIf config.features.desktop (builtins.attrValues scripts);
    };
}
