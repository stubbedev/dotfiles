{ config, pkgs, lib, ... }:

let
  iconThemeName = "Vimix-dark";
  cursorThemeName = "Vimix-cursors";

  setupScript = pkgs.writeShellScript "setup-snap-themes" ''
    set -e

    # Skip if snapd isn't installed
    if [ ! -d "/var/lib/snapd/desktop" ]; then
      exit 0
    fi

    # Find sudo in common locations
    SUDO=""
    for path in /usr/bin/sudo /bin/sudo /run/wrappers/bin/sudo; do
      if [ -x "$path" ]; then
        SUDO="$path"
        break
      fi
    done

    if [ -z "$SUDO" ]; then
      echo "Error: sudo not found. Please install sudo or run manually."
      exit 1
    fi

    ICON_DIR="/var/lib/snapd/desktop/icons"

    if [ -d "$ICON_DIR/${iconThemeName}" ] && [ -d "$ICON_DIR/${cursorThemeName}" ]; then
      exit 0
    fi

    echo ""
    echo "--------------------------------------------------------------------"
    echo "Snap desktop themes missing"
    echo "--------------------------------------------------------------------"
    echo ""
    echo "Snap apps can only see themes installed under /var/lib/snapd/desktop."
    echo "This will install the Vimix icon and cursor themes for snaps."
    echo ""
    read -p "Install Vimix icon/cursor themes for snaps? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      $SUDO mkdir -p "$ICON_DIR"
      $SUDO cp -a "${pkgs.vimix-icon-theme}/share/icons/${iconThemeName}" "$ICON_DIR/"
      $SUDO cp -a "${pkgs.vimix-cursors}/share/icons/${cursorThemeName}" "$ICON_DIR/"
      echo ""
      echo "Installed Vimix themes for snap apps."
    else
      echo ""
      echo "Skipped. You can install them later by running:"
      echo "  home-manager switch --flake . --impure"
    fi
    echo ""
  '';
in
''
  ${setupScript}
''
