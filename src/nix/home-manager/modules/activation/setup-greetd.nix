_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupGreetd";
  activationName = "setupGreetd";
  scriptName = "setup-greetd";
  after = order.after.setupGreetd;
  enableIf = { config, ... }: config.features.greetd;
  sudoArgs = { config, ... }:
    let
      configPath = "/etc/greetd/config.toml";
      servicePath = "/etc/systemd/system/greetd.service";

      # Read template and substitute the home directory path
      configTemplate = builtins.readFile ../../../../greetd/config.toml;
      # For now, keep the template simple - tuigreet will use the nix profile binary
      configContent = configTemplate;

      serviceContent = ''
        [Unit]
        Description=greetd - A minimal and flexible login manager
        Documentation=man:greetd(1)
        Documentation=https://git.sr.ht/~kennylevinsen/greetd

        # Make sure we are started after logins are permitted
        After=systemd-user-sessions.service
        After=plymouth-quit-wait.service

        # Don't conflict with getty on the VT we're using
        Conflicts=getty@tty1.service
        After=getty@tty1.service

        # Make sure the VT is cleared before we start
        Before=graphical.target
        Wants=graphical.target

        [Service]
        Type=simple
        ExecStart=${config.home.homeDirectory}/.nix-profile/bin/greetd
        Restart=on-failure

        # Disable sandboxing to allow greetd to start sessions
        ProtectSystem=no
        ProtectHome=no

        # Create a new session for the greeter
        PAMName=greetd

        # Use a specific TTY
        StandardInput=tty
        StandardOutput=tty
        StandardError=journal
        TTYPath=/dev/tty1
        TTYReset=yes
        TTYVHangup=yes
        TTYVTDisallocate=yes

        [Install]
        WantedBy=graphical.target
      '';

      pamContent = ''
        #%PAM-1.0
        # greetd PAM configuration
        auth       include      system-local-login
        account    include      system-local-login
        password   include      system-local-login
        session    include      system-local-login
      '';

      pamPath = "/etc/pam.d/greetd";
    in
    {
      preCheck = ''
        needsSetup=0

        # Check if config exists and is correct
        if [ ! -f "${configPath}" ]; then
          needsSetup=1
        fi

        # Check if service exists
        if [ ! -f "${servicePath}" ]; then
          needsSetup=1
        fi

        # Check if PAM config exists
        if [ ! -f "${pamPath}" ]; then
          needsSetup=1
        fi

        # Check if greetd service is enabled
        if ! systemctl is-enabled greetd.service &>/dev/null; then
          needsSetup=1
        fi

        if [ "$needsSetup" -eq 0 ]; then
          exit 0
        fi
      '';
      promptTitle = "⚠️  greetd display manager setup needed";
      promptBody = ''
        echo "greetd is a minimal and flexible login manager."
        echo "This will:"
        echo "  1. Install greetd configuration to /etc/greetd/"
        echo "  2. Install greetd systemd service"
        echo "  3. Install greetd PAM configuration"
        echo "  4. Disable SDDM service (if enabled)"
        echo "  5. Disable getty@tty1 service"
        echo "  6. Enable and start greetd service"
        echo ""
        echo "⚠️  WARNING: This will change your login manager!"
        echo "Make sure you have a way to access your system if something goes wrong."
      '';
      promptQuestion = "Set up greetd as your display manager?";
      actionScript = ''
        echo ""
        echo "Setting up greetd..."

        # Create config directory
        sudo mkdir -p /etc/greetd

        # Install config
        echo "${configContent}" | sudo tee "${configPath}" > /dev/null
        echo "✓ Config installed to ${configPath}"

        # Install systemd service
        echo "${serviceContent}" | sudo tee "${servicePath}" > /dev/null
        echo "✓ Service installed to ${servicePath}"

        # Install PAM config
        echo "${pamContent}" | sudo tee "${pamPath}" > /dev/null
        echo "✓ PAM config installed to ${pamPath}"

        # Reload systemd
        sudo systemctl daemon-reload
        echo "✓ Systemd daemon reloaded"

        # Disable other display managers
        for dm in sddm lightdm gdm ly@tty2; do
          if systemctl is-enabled "$dm.service" &>/dev/null; then
            sudo systemctl disable "$dm.service"
            echo "✓ Disabled $dm.service"
          fi
        done

        # Disable getty on tty1
        if systemctl is-enabled getty@tty1.service &>/dev/null; then
          sudo systemctl disable getty@tty1.service
          echo "✓ Disabled getty@tty1.service"
        fi

        # Enable greetd
        sudo systemctl enable greetd.service
        echo "✓ Enabled greetd.service"

        echo ""
        echo "✓ greetd setup completed successfully!"
        echo ""
        echo "To apply changes, you need to reboot your system."
        echo "After reboot, greetd with tuigreet will be your login manager."
      '';
      skipMessage =
        "Skipped. You can set up greetd later by running: home-manager switch --flake . --impure";
    };
}
