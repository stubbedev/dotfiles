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
      alacrittyReal = homeLib.gfxName "alacritty-real" pkgs.alacritty;
      alacrittyWrapped = pkgs.writeShellScriptBin "alacritty" ''
        real="${alacrittyReal}/bin/alacritty-real"

        case "''${1:-}" in
          --daemon|msg|--help|-h|--version|-V)
            exec "$real" "$@"
            ;;
        esac

        if "$real" msg create-window "$@" >/dev/null 2>&1; then
          exit 0
        fi

        "$real" --daemon >/dev/null 2>&1 &

        attempts=0
        while [ "$attempts" -lt 25 ]; do
          attempts=$((attempts + 1))
          if "$real" msg create-window "$@" >/dev/null 2>&1; then
            exit 0
          fi
          sleep 0.04
        done

        exec "$real" "$@"
      '';
      # Logseq's bundled chrome-sandbox can't be SUID from /nix/store; pass
      # --disable-setuid-sandbox so it falls back to userns. Matching
      # AppArmor profile installed by setup-logseq-apparmor on Ubuntu 24.04+.
      logseqPackage = homeLib.mkWrappedPackage {
        pkg = pkgs.logseq;
        flags = [ "--disable-setuid-sandbox" ];
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

        # Note-taking / knowledge base (Electron, GPU accelerated)
        logseqPackage
      ];
    };
}
