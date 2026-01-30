{ ... }:
{
  flake.modules.homeManager.xdgHypr =
    { config, lib, pkgs, systemInfo, homeLib, hy3, ... }:
    lib.mkIf config.features.hyprland {
      xdg.configFile = homeLib.xdgSources [
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
      ] // {
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
              hy3-plugin = hy3.packages.${pkgs.stdenv.hostPlatform.system}.hy3;
            in
            ''
              # Hyprland plugins loaded from Nix
              plugin = ${hy3-plugin}/lib/libhy3.so
            '';
        };
      };
    };
}
