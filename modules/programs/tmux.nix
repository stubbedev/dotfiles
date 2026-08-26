_: {
  flake.modules.homeManager.programsTmux =
    {
      self,
      lib,
      config,
      pkgs,
      ...
    }:
    let
      # lazy-tmux replaces resurrect+continuum: it snapshots window names,
      # layouts, pane commands and shell scrollback, and restores *one* session
      # on demand (`wakeup --session`) instead of every session at server
      # start. Its claude integration records the Claude Code session id and
      # restores the pane as `claude --resume <id>`, so Alt+f on a repo brings
      # the conversation back instead of a fresh one.
      #
      # The pin lives in _lazy-tmux.nix so modules/checks/tmux-session.nix can
      # test against the same binary this installs.
      lazy-tmux = pkgs.callPackage (self + "/modules/packages/_lazy-tmux.nix") { };
    in
    lib.mkIf config.features.desktop {
      home.file.".config/tmux/scripts/commands.sh" = {
        source = self + "/src/tmux/scripts/commands.sh";
        executable = true;
      };

      # Single source of truth for save behaviour: the daemon, `save_state` on
      # detach and the Alt+f restore path all read this instead of repeating
      # flags at every call site. scrollback is opt-in upstream. 1m matches the
      # old @continuum-save-interval and costs ~36K for every live session with
      # 10k lines of scrollback, so the interval is not worth stretching.
      home.file.".config/lazy-tmux/lazy-tmux.toml".text = ''
        save_interval = "1m"

        [scrollback]
        enabled = true
        lines = 10000
      '';

      home.packages = [ lazy-tmux ];

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        extraConfig = builtins.readFile (self + "/src/tmux/tmux.conf") + ''

          # ==============================================
          # lazy-tmux autosave daemon
          # ==============================================
          # Started per tmux server, killed with it. The daemon flocks a file
          # keyed by the tmux socket path, so re-sourcing this file on M-r
          # exits non-zero instead of stacking a second daemon — hence the
          # `|| true`. Interval and scrollback come from lazy-tmux.toml.
          run-shell -b '${lazy-tmux}/bin/lazy-tmux daemon >/dev/null 2>&1 || true'

          # Saved-session picker (includes sessions that are not running).
          # M-o is deliberately left unbound in tmux so it falls through to
          # the zsh `^[o` -> nvim binding (src/zsh/settings).
          bind -n M-i display-popup -B -w 70% -h 75% -E '${lazy-tmux}/bin/lazy-tmux picker'
        '';
        plugins = with pkgs.tmuxPlugins; [ yank ];
      };
    };
}
