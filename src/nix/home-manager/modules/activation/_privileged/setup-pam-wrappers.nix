_: {
  enableIf = { config, ... }: config.features.hyprland;
  args = _: {
    promptTitle = "⚠️  Nix PAM wrapper setup required for hyprlock authentication";
    promptBody = ''
      This will install a systemd service to enable password authentication
      for hyprlock. The service will persist across reboots.
    '';
    promptQuestion = "Install nix-pam-wrappers.service?";
    actionScript = ''
      sudo tee /etc/systemd/system/nix-pam-wrappers.service > /dev/null << 'EOF'
      [Unit]
      Description=Setup Nix PAM wrappers for non-NixOS systems
      DefaultDependencies=no
      Before=sysinit.target
      ConditionPathExists=!/run/wrappers/bin/unix_chkpwd

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/usr/bin/mkdir -p /run/wrappers/bin
      ExecStart=/usr/bin/ln -sf /usr/sbin/unix_chkpwd /run/wrappers/bin/unix_chkpwd

      [Install]
      WantedBy=sysinit.target
      EOF
      sudo systemctl daemon-reload
      sudo systemctl enable --now nix-pam-wrappers.service
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
