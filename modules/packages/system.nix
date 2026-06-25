# System services and utilities
_: {
  linuxOnlyHomeModules.packagesSystem =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # nixGL-wrapped alacritty (name preserved). The systemd user service
      # `alacritty-daemon` (modules/home/systemd.nix) runs `--daemon` from this
      # same derivation; the thin client below attaches new windows to it over
      # the shared IPC socket. Keep homeLib.alacrittySocket in sync with the
      # unit's --socket path.
      alacrittyGfx = homeLib.gfx pkgs.alacritty;

      # `alacritty` on PATH: attach a window to the running daemon so every
      # terminal shares one process. Single-instance lifecycle is owned by the
      # systemd unit, so this is a thin client — no spawn/poll race. Falls back
      # to a standalone window if the daemon socket isn't up yet (e.g. an early
      # login before the unit reaches its target). Control/query subcommands
      # pass straight through.
      alacrittyClient = pkgs.writeShellScriptBin "alacritty" ''
        real="${alacrittyGfx}/bin/alacritty"
        socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/alacritty.sock"

        case "''${1:-}" in
          --daemon|msg|--help|-h|--version|-V)
            exec "$real" "$@"
            ;;
        esac

        if "$real" msg --socket "$socket" create-window "$@" >/dev/null 2>&1; then
          exit 0
        fi
        exec "$real" "$@"
      '';
      # symlinkJoin the client (first-wins → shadows upstream bin/alacritty)
      # with upstream alacritty for Alacritty.desktop + icons. writeShellScriptBin
      # alone emits only bin/, so without this the desktop entry is absent on both
      # targets and alacritty never shows in rofi. The .desktop's Exec=alacritty
      # resolves to the client on PATH.
      alacrittyWrapped = pkgs.symlinkJoin {
        name = "alacritty-${pkgs.alacritty.version}";
        paths = [
          alacrittyClient
          pkgs.alacritty
        ];
        meta = pkgs.alacritty.meta // {
          mainProgram = "alacritty";
          # symlinkJoin yields a single `out` (terminfo merged in); inheriting
          # alacritty's multi-output outputsToInstall would make buildEnv fail
          # on the missing output. Same fix as lib.nix mkWrappedPackage.
          outputsToInstall = [ "out" ];
        };
      };

    in
    lib.mkIf config.features.desktop {
      home.packages = with pkgs; [
        # Terminal emulator (GPU accelerated)
        alacrittyWrapped

        # Network management (GUI applets)
        networkmanagerapplet
        networkmanager-openconnect

        # Bluetooth (GUI)
        blueman

        # Monitor Brightness (CLI tools)
        brightnessctl
        ddcutil

        # Clipboard managers (CLI/daemon)
        clipman
        cliphist

        # Mail (TUI, no GPU needed)
        mailutils
        aerc
        khard
        vdirsyncer

        # Keyring management (for automatic password management)
        # Note: Uses system-installed GNOME Keyring and KDE Wallet from Fedora
        libsecret # Provides secret-tool command

        # Cursor and icon themes
        vimix-cursors
        vimix-icon-theme

        util-linux

        # file manager
        yazi
        pcmanfm
      ];
    };
}
