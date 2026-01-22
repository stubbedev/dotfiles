{ config, lib, pkgs, ... }@args:
let
  homeLib = import ./lib.nix { inherit lib; };
  constants = import ./constants.nix { inherit config; };

  homePackages = homeLib.safeLoadPackagesFromDir ./packages
    (args // { inherit systemInfo; });
  programs = homeLib.loadModulesFromDir ./programs;

  # Load VPN scripts dynamically
  vpnConfigs = homeLib.loadVpnConfigs ./../../vpn;

  # Auto-detect system information
  hasNvidia = builtins.pathExists /proc/driver/nvidia/version;

  # Detect OS distribution
  osReleasePath = /etc/os-release;
  osReleaseContent = if builtins.pathExists osReleasePath then
    builtins.readFile osReleasePath
  else
    "";
  isFedora = builtins.match ".*ID=fedora.*" osReleaseContent != null;

  # System-specific library paths and nixGL wrapper selection
  systemInfo = {
    inherit hasNvidia isFedora;
    libPath = if isFedora then "lib64" else "lib";
    # Select the appropriate nixGL wrapper based on GPU detection
    nixGLWrapper =
      if hasNvidia then pkgs.nixgl.nixGLNvidia else pkgs.nixgl.nixGLIntel;
  };
in {
  targets.genericLinux = {
    enable = true;
    nixGL = { packages = pkgs.nixgl; };
  };
  home = {

    username = constants.user.name;
    homeDirectory = "/home/${constants.user.name}";
    stateVersion = "25.11";
    packages = homePackages;
    sessionPath = [
      "$HOME/.cargo/bin"
      "$HOME/.nix-profile/bin"
      "$HOME/.local/bin"
      "$HOME/.local/share/flatpak/exports/bin"
      "/var/lib/flatpak/exports/bin"
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
    ];

    file = {
      ".zshrc".text = ''
        if [[ -f "${constants.paths.zsh}/init" ]]; then
          source ${constants.paths.zsh}/init
        fi
      '';
      ".ideavimrc".source = ./../../ideavim/ideavimrc;
      ".tmux.conf".source = ./../../tmux/tmux.conf;

      ".local/bin/open-mail" = {
        text = ''
          #!/usr/bin/env bash

          # Find terminal emulator
          terminal_emulator="$HOME/.cargo/bin/alacritty"
          if [[ ! -x "$terminal_emulator" ]]; then
            terminal_emulator="${config.home.homeDirectory}/.nix-profile/bin/alacritty"
          fi

          # Check if Hyprland is active and hyprctl is available
          if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
            # Use hyprctl dispatch exec to launch in the current workspace
            hyprctl dispatch exec "$terminal_emulator -e aerc"
          else
            # Launch normally
            $terminal_emulator -e aerc
          fi
        '';
        executable = true;
      };
      ".local/bin/unsubscribe-mail".source = ./../../aerc/scripts/unsubscribe;
      ".local/bin/setup-gp-nmcli" = {
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          VPN_NAME="vpn.konform.com"
          GATEWAY="vpn.konform.com"

          if nmcli connection show "$VPN_NAME" >/dev/null 2>&1; then
            echo "Connection '$VPN_NAME' already exists."
            exit 1
          fi

          read -rp "Username for ''${VPN_NAME}: " VPN_USER
          read -rsp "Password for ''${VPN_NAME}: " VPN_PASS
          echo

          nmcli connection add \
            type vpn \
            con-name "$VPN_NAME" \
            ifname -- \
            vpn-type openconnect \
            vpn.data "gateway=''${GATEWAY},protocol=gp" \
            vpn.user "$VPN_USER"

          nmcli connection modify "$VPN_NAME" vpn.secrets "password=$VPN_PASS"

          nmcli connection modify "$VPN_NAME" connection.autoconnect no

          echo "Created VPN '""''${VPN_NAME}""' (autoconnect disabled)."
          echo "Connect with: nmcli connection up \"''${VPN_NAME}\""
        '';
        executable = true;
      };

      ".icons/${constants.theme.iconTheme}".source =
        "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";
      ".icons/Vimix-cursors".source =
        "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";

      # Also symlink to .local/share/icons for better compatibility
      ".local/share/icons/Vimix-dark".source =
        "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";
      ".local/share/icons/Vimix-cursors".source =
        "${pkgs.vimix-cursors}/share/icons/Vimix-cursors";
      ".themes/${constants.theme.gtkTheme}".source =
        "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
      ".w3m".source = ./../../w3m;

      # Flatpak overrides for dark mode theming
      # Note: Qt/KDE flatpaks may have poor contrast because they use the Breeze
      # theme from their runtime, which may be different from your system theme.
      # For better appearance, consider using native packages for Qt apps.
      ".local/share/flatpak/overrides/global".text = ''
        [Context]
        filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;xdg-config/kdeglobals:ro;~/.themes:ro;~/.icons:ro;/nix/store:ro

        [Environment]
        GTK_THEME=Adwaita-dark
        QT_QPA_PLATFORMTHEME=kde
        QT_STYLE=breeze
        COLOR_SCHEME=prefer-dark
        GDK_BACKEND=wayland
      '';
    };

    sessionVariables = {
      # Nix configuration
      NIXPKGS_ALLOW_UNFREE = "1";
      NIXPKGS_ALLOW_INSECURE = "1";
      NIXOS_OZONE_WL = "1";

      # Editor and display
      EDITOR = "${config.home.homeDirectory}/.local/bin/nvim";
      DISPLAY = ":0";

      # Desktop entries (Flatpak + Nix)
      XDG_DATA_DIRS = lib.mkForce
        "${config.home.homeDirectory}/.local/share/flatpak/exports/share:${config.home.homeDirectory}/.nix-profile/share:/nix/var/nix/profiles/default/share:/var/lib/flatpak/exports/share:/usr/share/ubuntu:/usr/local/share:/usr/share:/var/lib/snapd/desktop:$XDG_DATA_DIRS";

      # Paging and documentation
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
      MANROFFOPT = "-c";
      PAGER = "${pkgs.more}/bin/more";

      # Go configuration
      GOROOT = "${config.home.homeDirectory}/.go";
      GOPATH = "${config.home.homeDirectory}/go";

      # Theme and custom variables
      # NOTE: GTK_THEME is NOT set here because GTK4 apps crash with it
      # GTK3 apps use the theme from ~/.config/gtk-3.0/settings.ini
      # GTK4 apps use the color-scheme preference (prefer-dark) from dconf
      GTK_THEME_VARIANT = "dark";

      # NOTE: GTK_USE_PORTAL is set in Hyprland's env.conf instead of here
      # to avoid breaking KDE Plasma which requires portals to function

      DEPLOYER_REMOTE_USER = "abs";
    };

    activation = {
      customBinInstall = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (import ./scripts/bin-install.nix { inherit config pkgs constants; });
      customShellCompletions = lib.hm.dag.entryAfter [ "customBinInstall" ]
        (import ./scripts/shell-completions.nix {
          inherit config pkgs constants;
        });
      customConfigCleanUp = lib.hm.dag.entryAfter [ "customShellCompletions" ]
        (import ./scripts/config-cleanup.nix {
          inherit config pkgs constants;
        });
      # Setup PAM wrappers for Nix on non-NixOS (interactive, prompts for sudo if needed)
      setupPamWrappers = lib.hm.dag.entryAfter [ "customConfigCleanUp" ]
        (import ./scripts/setup-pam-wrappers.nix { inherit config pkgs lib; });
      # Setup hyprlock PAM configuration
      setupHyprlockPam = lib.hm.dag.entryAfter [ "setupPamWrappers" ]
        (import ./scripts/setup-hyprlock-pam.nix { inherit config pkgs lib; });
      # Setup GNOME Keyring PAM integration
      setupHyprKeyringPam = lib.hm.dag.entryAfter [ "setupHyprlockPam" ]
        (import ./scripts/hypr-keyring-pam.nix { inherit pkgs; });
      # Setup SDDM session entry for Hyprland
      setupHyprSession = lib.hm.dag.entryAfter [ "setupHyprKeyringPam" ]
        (import ./scripts/setup-sddm-session.nix { inherit config pkgs lib; });
      # Install icon/cursor themes for snap apps
      setupSnapThemes = lib.hm.dag.entryAfter [ "setupHyprSession" ]
        (import ./scripts/setup-snap-themes.nix { inherit config pkgs lib; });
      # System checks - verifies system configuration and provides helpful warnings
      systemChecks = lib.hm.dag.entryAfter [ "setupSnapThemes" ]
        (import ./scripts/system-checks.nix { inherit config pkgs lib; });
      # Restart PipeWire after audio config changes
      restartPipewire = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        ${pkgs.systemd}/bin/systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
      '';
    };
  };

  imports = programs;

  # XDG Config files
  xdg.configFile = {
    "lazygit/config.yml".source = ./../../lazygit/config.yml;
    "ghostty".source = ./../../ghostty;
    "alacritty".source = ./../../alacritty;
    "rofi".source = ./../../rofi;
    "btop/themes/catppuccin_frappe.theme".source =
      ./../../btop/themes/catppuccin_frappe.theme;
    "btop/themes/catppuccin_latte.theme".source =
      ./../../btop/themes/catppuccin_latte.theme;
    "btop/themes/catppuccin_macchiato.theme".source =
      ./../../btop/themes/catppuccin_macchiato.theme;
    "btop/themes/catppuccin_mocha.theme".source =
      ./../../btop/themes/catppuccin_mocha.theme;
    "swaync".source = ./../../swaync;
    "sway".source = ./../../sway;
    "waybar".source = ./../../waybar;

    # Copy individual hypr config files (not as a directory to allow overriding env.conf)
    "hypr/hypridle.conf".source = ./../../hypr/hypridle.conf;
    "hypr/hyprland.conf".source = ./../../hypr/hyprland.conf;
    "hypr/hyprlock.conf".source = ./../../hypr/hyprlock.conf;
    "hypr/hyprpaper.conf".source = ./../../hypr/hyprpaper.conf;
    "hypr/hyprsunset.conf".source = ./../../hypr/hyprsunset.conf;
    "hypr/keybinds.conf".source = ./../../hypr/keybinds.conf;
    "hypr/monitors.conf".source = ./../../hypr/monitors.conf;
    "hypr/settings.conf".source = ./../../hypr/settings.conf;
    "hypr/theme.conf".source = ./../../hypr/theme.conf;
    "hypr/windowrule.conf".source = ./../../hypr/windowrule.conf;
    "hypr/scripts".source = ./../../hypr/scripts;

    # Generate dynamic Hyprland env.conf based on system detection
    "hypr/env.conf" = {
      text = ''
        env = XDG_CURRENT_DESKTOP,Hyprland
        env = XDG_SESSION_TYPE,wayland
        env = XDG_SESSION_DESKTOP,Hyprland
        env = XCURSOR_THEME,Vimix-cursors
        env = XCURSOR_SIZE,24
        # PATH and XDG_DATA_DIRS are set by Home Manager session variables

        # Force Wayland backend for GTK apps
        env = GDK_BACKEND,wayland

        # Fix GTK3 menu flickering in waybar (disable portal for menu handling in Hyprland)
        env = GTK_USE_PORTAL,0

        # Force dark mode for all applications
        # Don't set GTK_THEME for GTK4 apps - they use color-scheme preference
        env = QT_QPA_PLATFORMTHEME,kde
        env = QT_STYLE_OVERRIDE,Breeze
        env = COLOR_SCHEME,prefer-dark

        # Electron apps (VSCode, Discord, etc.) - force dark mode
        env = ELECTRON_OZONE_PLATFORM_HINT,auto

        # GPU driver configuration (auto-detected: ${
          if systemInfo.hasNvidia then "NVIDIA" else "Mesa"
        })
        ${lib.optionalString systemInfo.hasNvidia ''
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = LIBVA_DRIVER_NAME,nvidia
        ''}
      '';
    };

    # Generate dynamic Hyprland plugins configuration
    "hypr/plugins.conf" = {
      text = let
        # hy3 is already built against the correct hyprland from the flake
        hy3-plugin = args.hy3.packages.${pkgs.system}.hy3;
      in ''
        # Hyprland plugins loaded from Nix
        plugin = ${hy3-plugin}/lib/libhy3.so
      '';
    };
    "opencode/opencode.json".source = ./../../opencode/opencode.json;
    "opencode/AGENTS.md".source = ./../../opencode/AGENTS.md;
    "opencode/themes/catppuccin-mocha.json".source =
      ./../../opencode/catppuccin-mocha.json;

    "xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;kde;
    '';

    "aerc/aerc.conf".source = ./../../aerc/aerc.conf;
    "aerc/binds.conf".source = ./../../aerc/binds.conf;

    # PipeWire audio configuration for USB docks with KVM switches
    "pipewire/pipewire.conf.d/99-usb-dock.conf".source =
      ./../../pipewire/pipewire.conf.d/99-usb-dock.conf;
    "pipewire/pipewire-pulse.conf.d/99-usb-dock.conf".source =
      ./../../pipewire/pipewire-pulse.conf.d/99-usb-dock.conf;

    # Low-latency PipeWire configuration for screen sharing and camera
    "pipewire/pipewire.conf.d/10-screenshare-optimize.conf".text = ''
      # Low-latency configuration for screen sharing, camera, and microphone
      # This is loaded before 99-usb-dock.conf but stream-specific settings take precedence

      # Stream-specific properties for screen capture
      stream.properties = {
          # Lower latency for screen capture
          node.latency = 512/48000  # ~10ms for screen sharing
      }

      # Camera/Video specific optimizations
      context.modules = [
          {   name = libpipewire-module-rt
              args = {
                  nice.level   = -11
                  rt.prio      = 88
                  rt.time.soft = -1
                  rt.time.hard = -1
              }
              flags = [ ifexists nofail ]
          }
      ]
    '';

    # PulseAudio client config for flatpak apps (prevents audio popping)
    "pulse/client.conf".source = ./../../pipewire/pulse-client.conf;

    # WirePlumber ALSA configuration for USB dock stability
    "wireplumber/main.lua.d/51-alsa-usb-dock.lua".source =
      ./../../wireplumber/main.lua.d/51-alsa-usb-dock.lua;

    # WirePlumber configuration to enable HDMI/DisplayPort audio
    "wireplumber/main.lua.d/50-enable-hdmi-audio.lua".source =
      ./../../wireplumber/main.lua.d/50-enable-hdmi-audio.lua;

    # GPG agent configuration
    "gnupg/gpg-agent.conf".text = ''
      # Use pinentry-gnome3 for password prompts (Wayland compatible)
      # pinentry-gnome3 integrates with gnome-keyring to remember passphrases
      pinentry-program ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3

      # Cache passwords for maximum time to avoid repeated prompts during session
      # 1 year = 31536000 seconds
      default-cache-ttl 31536000
      max-cache-ttl 31536000

      # Allow preset passphrases
      allow-preset-passphrase

      # SSH support is handled by gnome-keyring instead
      # enable-ssh-support
    '';
  } // vpnConfigs;

  systemd.user.services = {
    xdg-desktop-portal-hyprland = {
      Unit = {
        Description = "Portal service (Hyprland implementation)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.impl.portal.desktop.hyprland";
        ExecStart =
          "${pkgs.xdg-desktop-portal-hyprland}/libexec/xdg-desktop-portal-hyprland";
        Restart = "on-failure";
      };
    };

    await-powerprofile = {
      Unit = {
        Description = "Reload Waybar when power-profiles-daemon starts";
        After = [ "default.target" "power-profiles-daemon.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart =
          "${constants.paths.hypr}/scripts/service.await.sh power-profiles-daemon.service";
        Restart = "no";
      };
    };
    await-bluetooth = {
      Unit = {
        Description = "Reload Waybar when bluetooth starts";
        After = [ "default.target" "bluetooth.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart =
          "${constants.paths.hypr}/scripts/service.await.sh bluetooth.service";
        Restart = "no";
      };
    };
  };

  programs.home-manager.enable = true;

  nix = {
    package = pkgs.nix;
    settings = {
      # Prefer binary caches to avoid compilation
      substituters =
        [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
}
