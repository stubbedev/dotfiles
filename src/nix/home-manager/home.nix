{ config, lib, pkgs, ... }@args:
let
  constants = import ./constants.nix { inherit config; };

  # Auto-detect system information
  hasNvidia =
    builtins.pathExists (homeLib.toPath "/proc/driver/nvidia/version");

  # Detect OS distribution
  osReleasePath = /etc/os-release;
  osReleaseContent =
    if builtins.pathExists osReleasePath then
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

  homeLib = import ./lib.nix { inherit lib pkgs systemInfo; };

  homePackages = homeLib.safeLoadPackagesFromDir ./packages
    (args // { inherit systemInfo homeLib; });
  programs = homeLib.loadModulesFromDir ./programs;

  # Load VPN scripts/config dynamically
  vpnConfigs = homeLib.loadVpnConfigs ./../../vpn;
  vpnScripts = homeLib.loadVpnScripts ./../../vpn;
in
{
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
          if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
            hyprctl dispatch exec "${constants.paths.term} -e aerc"
          else
            ${constants.paths.term} -e aerc
          fi
        '';
        executable = true;
      };
      ".local/bin/konform-vpn-waybar" = {
        source = ./../../vpn/konform/waybar.sh;
        executable = true;
      };
      ".local/bin/unsubscribe-mail".source = ./../../aerc/scripts/unsubscribe;

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
        filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;~/.themes:ro;~/.icons:ro;/nix/store:ro

        [Environment]
        GTK_THEME=Adwaita-dark
        QT_QPA_PLATFORMTHEME=kde
        QT_STYLE=breeze
        COLOR_SCHEME=prefer-dark
        GDK_BACKEND=wayland,x11
      '';

      # Steam Flatpak override for X11/GLX support in KDE Wayland
      # Grants access to XDG_RUNTIME_DIR for XAUTHORITY and Discord RPC
      ".local/share/flatpak/overrides/com.valvesoftware.Steam" = {
        text = ''
          [Context]
          filesystems=/run/user/1000
        '';
        force = true;
      };
    } // vpnScripts;

    sessionVariables = {
      # Nix configuration
      NIXPKGS_ALLOW_UNFREE = "1";
      NIXPKGS_ALLOW_INSECURE = "1";
      NIXOS_OZONE_WL = "1";

      # Editor and display
      EDITOR = "${config.home.homeDirectory}/.local/bin/nvim";
      # DISPLAY = ":0";

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
      GTK_THEME_VARIANT = "dark";
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
        (import ./scripts/setup-pam-wrappers.nix {
          inherit config pkgs lib homeLib;
        });
      # Setup hyprlock PAM configuration
      setupHyprlockPam = lib.hm.dag.entryAfter [ "setupPamWrappers" ]
        (import ./scripts/setup-hyprlock-pam.nix {
          inherit config pkgs lib homeLib;
        });
      # Setup GNOME Keyring PAM integration
      setupHyprKeyringPam = lib.hm.dag.entryAfter [ "setupHyprlockPam" ]
        (import ./scripts/hypr-keyring-pam.nix { inherit pkgs; });
      # Setup SDDM session entry for Hyprland
      setupHyprSession = lib.hm.dag.entryAfter [ "setupHyprKeyringPam" ]
        (import ./scripts/setup-sddm-session.nix {
          inherit config pkgs lib homeLib;
        });
      # Install icon/cursor themes for snap apps
      setupSnapThemes = lib.hm.dag.entryAfter [ "setupHyprSession" ]
        (import ./scripts/setup-snap-themes.nix {
          inherit config pkgs lib homeLib;
        });
      # Polkit rule for passwordless VPN pkexec usage
      setupVpnPolkit = lib.hm.dag.entryAfter [ "setupSnapThemes" ]
        (import ./scripts/setup-vpn-polkit.nix {
          inherit config pkgs lib homeLib;
        });
      # Polkit rule for CPU frequency scaling fix
      setupPowerProfileFix = lib.hm.dag.entryAfter [ "setupVpnPolkit" ]
        (import ./scripts/setup-power-profile-fix.nix {
          inherit config pkgs lib homeLib;
        });
      # GRUB config for intel_pstate passive mode
      setupGrubIntelPstate = lib.hm.dag.entryAfter [ "setupPowerProfileFix" ]
        (import ./scripts/setup-grub-intel-pstate.nix {
          inherit config pkgs lib homeLib;
        });
      # System checks - verifies system configuration and provides helpful warnings
      systemChecks = lib.hm.dag.entryAfter [ "setupGrubIntelPstate" ]
        (import ./scripts/system-checks.nix { inherit config pkgs lib; });
      # Restart Waybar after home-manager switch
      restartWaybar = lib.hm.dag.entryAfter [ "systemChecks" ] ''
        if command -v systemctl >/dev/null 2>&1; then
          $DRY_RUN_CMD systemctl --user restart waybar.service || true
        fi
      '';
    };
  };

  imports = programs;

  # XDG Config files
  xdg.configFile = homeLib.xdgSources [
    "lazygit/config.yml"
    "alacritty"
    "rofi"
    "btop/themes/catppuccin_frappe.theme"
    "btop/themes/catppuccin_latte.theme"
    "btop/themes/catppuccin_macchiato.theme"
    "btop/themes/catppuccin_mocha.theme"
    "swaync"
    "waybar"

    # Copy individual hypr config files (not as a directory to allow overriding env.conf)
    "hypr/hypridle.conf"
    "hypr/hyprland.conf"
    "hypr/hyprlock.conf"
    "hypr/hyprpaper.conf"
    "hypr/hyprsunset.conf"
    "hypr/keybinds.conf"
    "hypr/monitors.conf"
    "hypr/settings.conf"
    "hypr/theme.conf"
    "hypr/windowrule.conf"
    "hypr/scripts"

    "opencode/opencode.json"
    "opencode/AGENTS.md"
    "opencode/themes/catppuccin-mocha.json"

    "aerc/aerc.conf"
    "aerc/binds.conf"

    # PipeWire audio configuration for USB docks with KVM switches
    "pipewire/pipewire.conf.d/99-usb-dock.conf"
    "pipewire/pipewire-pulse.conf.d/99-usb-dock.conf"
    # Low-latency PipeWire configuration for screen sharing and camera
    "pipewire/pipewire.conf.d/10-screenshare-optimize.conf"

    # WirePlumber ALSA configuration for USB dock stability
    "wireplumber/main.lua.d/51-alsa-usb-dock.lua"

    # WirePlumber configuration to enable HDMI/DisplayPort audio
    "wireplumber/main.lua.d/50-enable-hdmi-audio.lua"

    # WirePlumber configuration to stop Bluetooth auto profile switching
    "wireplumber/main.lua.d/60-disable-bt-autoswitch.lua"

    "xdg-desktop-portal/portals.conf"
  ] // {
    # KDE Plasma Wayland configuration to use nixGL-wrapped Xwayland
    # This enables GLX support with NVIDIA drivers for X11 apps (like Steam)
    "kwinrc" = {
      text = lib.generators.toINI { } {
        Xwayland = {
          Scale = 1;
          ServerPath = "${config.home.homeDirectory}/.nix-profile/bin/Xwayland";
          XwaylandEavesdrops = "None";
        };
      };
      force = true;
    };

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

        # Firefox: force native Wayland backend to keep video playback smooth
        env = MOZ_ENABLE_WAYLAND,1

        # GPU driver configuration (auto-detected: ${
          if systemInfo.hasNvidia then "NVIDIA" else "Mesa"
        })
        ${lib.optionalString systemInfo.hasNvidia ''
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = LIBVA_DRIVER_NAME,nvidia
          env = MOZ_DISABLE_RDD_SANDBOX,1
          env = NVD_BACKEND,direct
        ''}
      '';
    };

    # Generate dynamic Hyprland plugins configuration
    "hypr/plugins.conf" = {
      text =
        let
          # hy3 is already built against the correct hyprland from the flake
          hy3-plugin = args.hy3.packages.${pkgs.system}.hy3;
        in
        ''
          # Hyprland plugins loaded from Nix
          plugin = ${hy3-plugin}/lib/libhy3.so
        '';
    };
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
        Description = "Restart Waybar when power-profiles-daemon starts";
        After = [ "default.target" "power-profiles-daemon.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user restart waybar.service";
        Restart = "no";
      };
    };
    await-bluetooth = {
      Unit = {
        Description = "Restart Waybar when bluetooth starts";
        After = [ "default.target" "bluetooth.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --user restart waybar.service";
        Restart = "no";
      };
    };

    power-profile-fix = {
      Unit = {
        Description = "Fix CPU frequency scaling for power profiles";
        After = [ "default.target" "power-profiles-daemon.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "simple";
        ExecStart = "${constants.paths.hypr}/scripts/power-profile-fix.sh";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    waybar = {
      Unit = {
        Description = "Waybar - Highly customizable Wayland bar";
        Documentation = "https://github.com/Alexays/Waybar/wiki";
        After = [ "graphical-session.target" "power-profiles-daemon.service" ];
        Wants = [ "power-profiles-daemon.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
      Service = {
        Type = "simple";
        ExecStart = "${constants.paths.hypr}/scripts/waybar.launch.sh";
        ExecStopPost = "-${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -9 waybar || true; sleep 0.5'";
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  };

  programs.home-manager.enable = true;

  nix = {
    package = pkgs.nix;
    settings = {
      substituters =
        [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
}
