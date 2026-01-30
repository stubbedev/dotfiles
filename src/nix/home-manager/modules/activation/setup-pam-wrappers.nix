{ ... }:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupPamWrappers";
  activationName = "setupPamWrappers";
  scriptName = "setup-pam-wrappers";
  after = order.after.setupPamWrappers;
  enableIf = { config, ... }: config.features.hyprland;
  sudoArgs = { ... }:
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
    in
    {
      preCheck = ''
        if [ -e "${wrapperPath}" ]; then
          exit 0
        fi

        if [ -f "${servicePath}" ]; then
          echo "Service exists but wrapper missing, starting service..."
          sudo systemctl start nix-pam-wrappers.service
          exit 0
        fi
      '';
      promptTitle = "⚠️  Nix PAM wrapper setup required for hyprlock authentication";
      promptBody = ''
        echo "This will install a systemd service to enable password authentication"
        echo "for hyprlock. The service will persist across reboots."
      '';
      promptQuestion = "Install nix-pam-wrappers.service?";
      actionScript = ''
        echo "${serviceContent}" | sudo tee "${servicePath}" > /dev/null
        sudo systemctl daemon-reload
        sudo systemctl enable --now nix-pam-wrappers.service
        echo ""
        echo "✓ Service installed and started successfully!"
      '';
      skipMessage =
        "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
