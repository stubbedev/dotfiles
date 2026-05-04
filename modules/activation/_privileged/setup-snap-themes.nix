_: {
  enableIf = { config, ... }: config.features.theming;
  args =
    { pkgs, ... }:
    {
      preCheck = ''
        if [ ! -d "/var/lib/snapd/desktop" ]; then
          exit 0
        fi
      '';
      promptTitle = "Snap desktop themes missing";
      promptBody = ''
        Snap apps can only see themes installed under /var/lib/snapd/desktop.
        This will install the Vimix icon and cursor themes for snaps.
      '';
      promptQuestion = "Install Vimix icon/cursor themes for snaps?";
      actionScript = ''
        ICON_DIR="/var/lib/snapd/desktop/icons"
        sudo mkdir -p "$ICON_DIR"
        sudo cp -a "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark" "$ICON_DIR/"
        sudo cp -a "${pkgs.vimix-cursors}/share/icons/Vimix-cursors" "$ICON_DIR/"
      '';
      skipMessage = "Skipped. You can install them later by running: home-manager switch --flake . --impure";
    };
}
