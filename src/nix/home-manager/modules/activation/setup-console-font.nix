_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupConsoleFont";
  activationName = "setupConsoleFont";
  scriptName = "setup-console-font";
  after = order.after.setupConsoleFont;
  enableIf = { config, ... }: config.features.greetd or false;
  sudoArgs =
    { config, pkgs, ... }:
    let
      servicePath = "/etc/systemd/system/console-font.service";
      
      # vconsole.conf for persistent font configuration
      vconsolePath = "/etc/vconsole.conf";
      
      # Get the terminus font path from the package
      terminusFontPath = "${pkgs.terminus_font}/share/consolefonts";
      fontName = "ter-132n";  # Large, clear Terminus font
      
      serviceContent = ''
        [Unit]
        Description=Set console font for greetd
        DefaultDependencies=no
        After=systemd-vconsole-setup.service
        Before=greetd.service
        
        [Service]
        Type=oneshot
        # Use Terminus font from home-manager nix profile
        # This ensures the font exists regardless of system packages
        ExecStart=/usr/bin/setfont ${config.home.homeDirectory}/.nix-profile/share/consolefonts/${fontName}
        StandardOutput=journal
        StandardError=journal
        RemainAfterExit=yes
        
        [Install]
        WantedBy=multi-user.target
      '';
      
      vconsoleContent = ''
        # Console font configuration for TTY
        # This sets a larger, more readable Terminus font for greetd/tuigreet
        # Font is installed via home-manager (terminus_font package)
        # Note: TTY cannot use TrueType fonts (like JetBrains Mono)
        # Only PSF/PSFU bitmap fonts work in TTY
        FONT=${config.home.homeDirectory}/.nix-profile/share/consolefonts/${fontName}
      '';
    in
    {
      preCheck = ''
        needsSetup=0
        
        # Check if service exists
        if [ ! -f "${servicePath}" ]; then
          needsSetup=1
        fi
        
        # Check if vconsole.conf exists with correct font
        if ! grep -q "FONT=ter-132n" "${vconsolePath}" 2>/dev/null; then
          needsSetup=1
        fi
        
        # Check if service is enabled
        if ! systemctl is-enabled console-font.service &>/dev/null; then
          needsSetup=1
        fi
        
        if [ "$needsSetup" -eq 0 ]; then
          exit 0
        fi
      '';
      promptTitle = "⚠️  Console font setup for greetd";
      promptBody = ''
        echo "To make greetd/tuigreet more readable, we'll set a larger console font."
        echo ""
        echo "⚠️  IMPORTANT: TTY consoles can ONLY use PSF bitmap fonts"
        echo "   JetBrains Mono (from home-manager) is a TrueType font and won't work in TTY"
        echo ""
        echo "This will:"
        echo "  1. Use Terminus font (ter-132n) from home-manager's terminus_font package"
        echo "  2. Install a systemd service to set the console font at boot"
        echo "  3. Configure /etc/vconsole.conf for persistent font settings"
        echo ""
        echo "Font: Terminus ter-132n - large (13x32px), clear, excellent Unicode support"
        echo "Installed via: home-manager (guaranteed to exist)"
        echo ""
        echo "Available Terminus variants in your nix profile:"
        echo "  ter-116n (smaller), ter-120n, ter-124n, ter-128n, ter-132n (largest)"
      '';
      promptQuestion = "Set up console font for better greetd readability?";
      actionScript = ''
        echo ""
        echo "Setting up console font..."
        
        # Install systemd service
        echo "${serviceContent}" | sudo tee "${servicePath}" > /dev/null
        echo "✓ Service installed to ${servicePath}"
        
        # Configure vconsole.conf
        if [ -f "${vconsolePath}" ]; then
          # Backup existing config
          sudo cp "${vconsolePath}" "${vconsolePath}.bak"
          echo "✓ Backed up existing ${vconsolePath}"
        fi
        
        echo "${vconsoleContent}" | sudo tee "${vconsolePath}" > /dev/null
        echo "✓ Console font configured in ${vconsolePath}"
        
        # Reload systemd
        sudo systemctl daemon-reload
        echo "✓ Systemd daemon reloaded"
        
        # Enable the service
        sudo systemctl enable console-font.service
        echo "✓ Enabled console-font.service"
        
        # Apply font immediately if we're in a TTY
        if [ -t 0 ] && command -v setfont &>/dev/null; then
          FONT_PATH="${config.home.homeDirectory}/.nix-profile/share/consolefonts/${fontName}"
          if [ -f "$FONT_PATH.psf.gz" ] || [ -f "$FONT_PATH" ]; then
            if sudo setfont "$FONT_PATH" 2>/dev/null; then
              echo "✓ Console font applied immediately"
            else
              echo "⚠ Could not apply font now"
              echo "  Font will be applied on next boot"
            fi
          else
            echo "⚠ Font file not found yet (may need to complete home-manager activation)"
            echo "  Font will be available after full activation completes"
          fi
        fi
        
        echo ""
        echo "✓ Console font setup completed!"
        echo ""
        echo "Font installed from: ${config.home.homeDirectory}/.nix-profile/share/consolefonts/"
        echo ""
        echo "To change font size, you can:"
        echo "  1. List Terminus variants: ls ${config.home.homeDirectory}/.nix-profile/share/consolefonts/"
        echo "  2. Edit /etc/vconsole.conf and change the FONT= path"
        echo "  3. Test immediately: sudo setfont ~/.nix-profile/share/consolefonts/ter-124n"
        echo ""
        echo "⚠️  Remember: TTY only supports PSF fonts, not TTF fonts like JetBrains Mono"
      '';
      skipMessage = "Skipped. You can set up console font later by running: home-manager switch --flake . --impure";
    };
}
