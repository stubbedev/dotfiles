# tmux, with lazy-tmux for session persistence.
#
# lazy-tmux replaced resurrect+continuum: it snapshots window names, layouts,
# pane commands and shell scrollback, and restores ONE session on demand
# (`wakeup --session`) instead of every session at server start. Its claude
# integration records the Claude Code session id and restores the pane as
# `claude --resume <id>`, so Alt+f on a repo brings the conversation back
# rather than a fresh one.
_: {
  flake.modules.homeManager.tmux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.packages = [ pkgs.lazy-tmux ];

      home.file.".config/tmux/scripts/commands.sh" = {
        source = pkgs.stubbe.renderPalette "src/tmux/commands.sh" { };
        executable = true;
      };

      # Single source of truth for save behaviour: the daemon, `save_state` on
      # detach and the Alt+f restore path all read this instead of repeating
      # flags at every call site. scrollback is opt-in upstream. 1m matches the
      # old @continuum-save-interval and costs ~36K per live session with 10k
      # lines of scrollback, so stretching the interval is not worth it.
      home.file.".config/lazy-tmux/lazy-tmux.toml".text = ''
        save_interval = "1m"

        [scrollback]
        enabled = true
        lines = 10000
      '';

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        plugins = [ pkgs.tmuxPlugins.yank ];
        extraConfig = builtins.readFile (pkgs.stubbe.renderPalette "src/tmux/tmux.conf" { }) + ''

          # ==============================================
          # lazy-tmux autosave daemon
          # ==============================================
          # Started per tmux server, killed with it. The daemon flocks a file
          # keyed by the tmux socket path, so re-sourcing this file on M-r
          # exits non-zero instead of stacking a second daemon — hence the
          # `|| true`. Interval and scrollback come from lazy-tmux.toml.
          run-shell -b '${lib.getExe pkgs.lazy-tmux} daemon >/dev/null 2>&1 || true'

          # Saved-session picker (includes sessions that are not running).
          # M-o is deliberately left unbound in tmux so it falls through to
          # the zsh `^[o` → nvim binding (src/shell/zsh/settings).
          bind -n M-i display-popup -B -w 70% -h 75% -E '${lib.getExe pkgs.lazy-tmux} picker'
        '';
      };
    };
}
