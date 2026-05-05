_: {
  enableIf = { config, ... }: config.features.theming;
  args =
    { pkgs, homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "Vimix icon/cursor themes for snaps";
      body = ''
        Snap apps can only see themes installed under /var/lib/snapd/desktop.
        This will install the Vimix icon and cursor themes for snaps.
      '';
      preCheck = homeLib.requirePath "/var/lib/snapd/desktop";
      actionScript = ''
        ICON_DIR="/var/lib/snapd/desktop/icons"
        sudo mkdir -p "$ICON_DIR"
        sudo cp -a "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark" "$ICON_DIR/"
        sudo cp -a "${pkgs.vimix-cursors}/share/icons/Vimix-cursors" "$ICON_DIR/"
      '';
    };
}
