# System services and utilities
{ ... }:
{
  flake.modules.homeManager.packagesSystem =
    { pkgs, homeLib, ... }:
    {
      home.packages = with pkgs; [
        # Terminal emulator (GPU accelerated)
        (homeLib.gfx alacritty)

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
      ];
    };
}
