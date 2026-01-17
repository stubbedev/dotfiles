{ config, pkgs, lib, ... }:

let
  wrapperPath = "/run/wrappers/bin/unix_chkpwd";
  servicePath = "/etc/systemd/system/nix-pam-wrappers.service";

  serviceContent = ''
    [Unit]
    Description=Setup Nix PAM wrappers for non-NixOS systems
    DefaultDependencies=no
    Before=sysinit.target
    ConditionPathExists=!${wrapperPath}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/bin/mkdir -p /run/wrappers/bin
    ExecStart=/usr/bin/ln -sf /usr/sbin/unix_chkpwd ${wrapperPath}

    [Install]
    WantedBy=sysinit.target
  '';

  setupScript = pkgs.writeShellScript "setup-pam-wrappers" ''
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

    # Check if wrapper exists
    if [ -e "${wrapperPath}" ]; then
      exit 0
    fi

    # Check if service is installed
    if [ -f "${servicePath}" ]; then
      echo "Service exists but wrapper missing, starting service..."
      $SUDO systemctl start nix-pam-wrappers.service
      exit 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Nix PAM wrapper setup required for hyprlock authentication"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This will install a systemd service to enable password authentication"
    echo "for hyprlock. The service will persist across reboots."
    echo ""
    read -p "Install nix-pam-wrappers.service? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      echo "${serviceContent}" | $SUDO tee "${servicePath}" > /dev/null
      $SUDO systemctl daemon-reload
      $SUDO systemctl enable --now nix-pam-wrappers.service
      echo ""
      echo "✓ Service installed and started successfully!"
    else
      echo ""
      echo "Skipped. You can install it later by running:"
      echo "  home-manager switch --flake . --impure"
    fi
    echo ""
  '';

in ''
  ${setupScript}
''
