_: {
  enableIf = { config, ... }: config.features.hyprland || config.features.niri;
  args =
    { lib, homeLib, ... }:
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
    in
    {
      promptTitle = "⚠️  Nix PAM wrapper setup required for wayle lock authentication";
      promptBody = ''
        This will install a systemd service to enable password authentication
        for wayle's session lock. The service will persist across reboots.
      '';
      promptQuestion = "Install nix-pam-wrappers.service?";
      actionScript = ''
        ${homeLib.installSystemFile {
          target = "/etc/systemd/system/nix-pam-wrappers.service";
          content = lib.generators.toINI { listsAsDuplicateKeys = true; } unit;
        }}
        sudo systemctl daemon-reload
        sudo systemctl enable --now nix-pam-wrappers.service
      '';
    };
}
