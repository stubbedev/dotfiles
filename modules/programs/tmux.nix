_: {
  flake.modules.homeManager.programsTmux =
    {
      self,
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file.".config/tmux/scripts/commands.sh" = {
        source = self + "/src/tmux/scripts/commands.sh";
        executable = true;
      };

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        # Home Manager emits plugins *before* extraConfig, so the theme block
        # in tmux.conf wins on any option both set — see the status-right
        # re-attach at the end of this list.
        extraConfig = builtins.readFile (self + "/src/tmux/tmux.conf") + ''

          # ==============================================
          # Continuum auto-save hook
          # ==============================================
          # Continuum polls for save work through an interpolation it prepends
          # to status-right at plugin load. The theme block above assigns
          # status-right outright and drops it, which is why saves only ever
          # happened by hand. Re-attach it here; the match guard keeps M-r
          # reloads (which re-source this file) from stacking copies, and the
          # string is byte-identical to continuum's so the plugin's own
          # idempotence check sees it too.
          if -F "#{==:#{m:*continuum_save.sh*,#{status-right}},0}" \
            "set -ag status-right '#(${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh)'"
        '';
        plugins = with pkgs.tmuxPlugins; [
          yank
          {
            plugin = resurrect;
            extraConfig = ''
              set -g @resurrect-capture-pane-contents 'on'
              # Hook values are bash-eval'd by resurrect, so $HOME expands at
              # run time — no need for the @stubbe_commands format, which is
              # only set further down in extraConfig.
              set -g @resurrect-hook-post-save-all    '$HOME/.config/tmux/scripts/commands.sh save_pins'
              set -g @resurrect-hook-post-restore-all '$HOME/.config/tmux/scripts/commands.sh restore_pins'
            '';
          }
          {
            # Must stay last: continuum reads resurrect's save/restore script
            # paths, which resurrect only sets once loaded.
            plugin = continuum;
            extraConfig = ''
              set -g @continuum-restore     'on'
              set -g @continuum-save-interval '1'
            '';
          }
        ];
      };
    };
}
