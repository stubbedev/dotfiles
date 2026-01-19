{ config, pkgs, lib, ... }:

let
  pamPath = "/etc/pam.d/hyprlock";

  pamContent = ''
    #%PAM-1.0
    # Minimal PAM config for hyprlock using only Nix PAM modules
    auth       sufficient   pam_unix.so nullok
    auth       required     pam_deny.so

    account    required     pam_unix.so

    password   required     pam_unix.so nullok

    session    required     pam_unix.so
  '';

  setupScript = pkgs.writeShellScript "setup-hyprlock-pam" ''
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

    # Check if PAM config exists
    if [ -f "${pamPath}" ]; then
      exit 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Hyprlock PAM configuration missing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Hyprlock needs a PAM configuration to authenticate passwords."
    echo "This will create a minimal Nix-compatible PAM config."
    echo ""
    read -p "Create ${pamPath}? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      echo "${pamContent}" | $SUDO tee "${pamPath}" > /dev/null
      echo ""
      echo "✓ PAM configuration created successfully!"
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
