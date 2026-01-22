{ pkgs, ... }:

let
  setupScript = pkgs.writeShellScript "hypr-keyring-pam" ''
    set -e

    authLine="auth optional pam_gnome_keyring.so"
    sessionLine="session optional pam_gnome_keyring.so auto_start"
    pamFiles=(
      /etc/pam.d/login
      /etc/pam.d/ly
      /etc/pam.d/lightdm
      /etc/pam.d/gdm
      /etc/pam.d/sddm
    )

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

    missingFiles=()
    for file in "${pamFiles[@]}"; do
      if [ ! -f "$file" ]; then
        continue
      fi

      missing=0
      grep -qF "$authLine" "$file" || missing=1
      grep -qF "$sessionLine" "$file" || missing=1

      if [ "$missing" -eq 1 ]; then
        missingFiles+=("$file")
      fi
    done

    if [ "${#missingFiles[@]}" -eq 0 ]; then
      exit 0
    fi

    echo ""
    echo "Missing GNOME Keyring PAM lines in:"
    for file in "${missingFiles[@]}"; do
      echo "  - $file"
    done
    echo ""
    read -p "Add GNOME Keyring PAM lines to these files? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      for file in "${missingFiles[@]}"; do
        grep -qF "$authLine" "$file" || printf '%s\n' "$authLine" | $SUDO tee -a "$file" > /dev/null
        grep -qF "$sessionLine" "$file" || printf '%s\n' "$sessionLine" | $SUDO tee -a "$file" > /dev/null
      done
      echo ""
      echo "✓ GNOME Keyring PAM lines added."
    else
      echo ""
      echo "Skipped GNOME Keyring PAM updates."
    fi
    echo ""
  '';

in ''
  ${setupScript}
''
