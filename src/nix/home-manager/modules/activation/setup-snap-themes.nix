{ ... }:
let
  helpers = import ./_helpers.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupSnapThemes";
  activationName = "setupSnapThemes";
  scriptName = "setup-snap-themes";
  after = [ "setupHyprSession" ];
  sudoArgs = { pkgs, ... }:
    let
      iconThemeName = "Vimix-dark";
      cursorThemeName = "Vimix-cursors";
    in
    {
      preCheck = ''
        if [ ! -d "/var/lib/snapd/desktop" ]; then
          exit 0
        fi

        ICON_DIR="/var/lib/snapd/desktop/icons"
        if [ -d "$ICON_DIR/${iconThemeName}" ] && [ -d "$ICON_DIR/${cursorThemeName}" ]; then
          exit 0
        fi
      '';
      promptTitle = "Snap desktop themes missing";
      promptBody = ''
        echo "Snap apps can only see themes installed under /var/lib/snapd/desktop."
        echo "This will install the Vimix icon and cursor themes for snaps."
      '';
      promptQuestion = "Install Vimix icon/cursor themes for snaps?";
      actionScript = ''
        sudo mkdir -p "$ICON_DIR"
        sudo cp -a "${pkgs.vimix-icon-theme}/share/icons/${iconThemeName}" "$ICON_DIR/"
        sudo cp -a "${pkgs.vimix-cursors}/share/icons/${cursorThemeName}" "$ICON_DIR/"
        echo ""
        echo "Installed Vimix themes for snap apps."
      '';
      skipMessage =
        "Skipped. You can install them later by running: home-manager switch --flake . --impure";
    };
}
