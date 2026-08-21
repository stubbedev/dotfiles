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
      # Not in nixpkgs and upstream ships no flake, so pin the release tarball
      # — a statically linked Go binary, nothing to compile. Bumping = new
      # version + that release's sha256 from its checksums.txt; hm's
      # bump_release_pins only rewrites `github:owner/repo/tag` flake inputs,
      # so this pin is manual. x86_64-linux only, which is every host here.
      lazy-tmux = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "lazy-tmux";
        version = "0.2.1";
        src = pkgs.fetchurl {
          url = "https://github.com/alchemmist/lazy-tmux/releases/download/v${finalAttrs.version}/lazy-tmux_linux_amd64.tar.gz";
          sha256 = "ec3d100fd5d297f2f91660977692c24f238896ae265999b32aede8fd1e91c2fa";
        };
        # Tarball has no top-level directory (bin, LICENSE, README side by side).
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          install -Dm755 lazy-tmux $out/bin/lazy-tmux
          runHook postInstall
        '';
        meta = {
          description = "Lazy tmux session saver and restorer";
          homepage = "https://lazy-tmux.xyz";
          license = lib.licenses.mit;
          mainProgram = "lazy-tmux";
          platforms = [ "x86_64-linux" ];
        };
      });
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
          bind -n M-o display-popup -B -w 70% -h 75% -E '${lazy-tmux}/bin/lazy-tmux picker'
        '';
        plugins = with pkgs.tmuxPlugins; [ yank ];
      };
    };
}
