_: {
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { lib, ... }:
    let
      unit = {
        Unit = {
          Description = "Setup Nix PAM wrappers for non-NixOS systems";
          DefaultDependencies = "no";
          Before = "sysinit.target";
          ConditionPathExists = "!/run/wrappers/bin/unix_chkpwd";
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = [
            "/usr/bin/mkdir -p /run/wrappers/bin"
            "/usr/bin/ln -sf /usr/sbin/unix_chkpwd /run/wrappers/bin/unix_chkpwd"
          ];
        };
        Install = {
          WantedBy = "sysinit.target";
        };
      };
      unitText = lib.generators.toINI { listsAsDuplicateKeys = true; } unit;
    in
    {
      promptTitle = "⚠️  Nix PAM wrapper setup required for hyprlock authentication";
      promptBody = ''
        This will install a systemd service to enable password authentication
        for hyprlock. The service will persist across reboots.
      '';
      promptQuestion = "Install nix-pam-wrappers.service?";
      actionScript = ''
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' EXIT
        cat > "$tmpfile" << 'EOF'
        ${unitText}EOF
        sudo install -m 0644 "$tmpfile" /etc/systemd/system/nix-pam-wrappers.service
        sudo systemctl daemon-reload
        sudo systemctl enable --now nix-pam-wrappers.service
      '';
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
