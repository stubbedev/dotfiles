{ config, pkgs, lib, ... }:

let
  desktopPath = "/usr/share/wayland-sessions/hyprland-nix.desktop";

  desktopContent = ''
    [Desktop Entry]
    Name=Hyprland (Nix)
    Comment=Hyprland Wayland Compositor from Nix/Home Manager
    Exec=${config.home.homeDirectory}/.nix-profile/bin/start-hyprland
    Type=Application
    DesktopNames=Hyprland
  '';

  setupScript = pkgs.writeShellScript "setup-sddm-session" ''
    set -e

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

    # Check if desktop entry exists
    if [ -f "${desktopPath}" ]; then
      exit 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  SDDM Hyprland session entry missing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "SDDM needs a desktop entry to show Hyprland in the session menu."
    echo "This will create the session entry for Hyprland (Nix)."
    echo ""
    read -p "Create ${desktopPath}? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      $SUDO mkdir -p /usr/share/wayland-sessions
      echo "${desktopContent}" | $SUDO tee "${desktopPath}" > /dev/null
      echo ""
      echo "✓ SDDM session entry created successfully!"
    else
      echo ""
      echo "Skipped. You can create it later by running:"
      echo "  home-manager switch --flake . --impure"
    fi
    echo ""
  '';

in ''
  ${setupScript}
''
