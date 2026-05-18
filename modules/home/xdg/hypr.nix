_: {
  flake.modules.homeManager.xdgHypr =
    {
      config,
      constants,
      lib,
      pkgs,
      systemInfo,
      homeLib,
      hy3,
      ...
    }:
    lib.mkIf config.features.hyprland {
      xdg.configFile =
        homeLib.xdgSources [
          # Copy individual hypr config files (not as a directory to allow overriding env.conf)
          "hypr/hypridle.conf"
          "hypr/hyprland.conf"
          "hypr/hyprlock.conf"
          "hypr/hyprpaper.conf"
          "hypr/hyprsunset.conf"
          "hypr/hyprtoolkit.conf"
          # "hypr/hyprlauncher.conf"
          "hypr/keybinds.conf"
          "hypr/monitors.conf"
          "hypr/settings.conf"
          "hypr/theme.conf"
          "hypr/windowrule.conf"
          "hypr/env.conf"
          "hypr/scripts"
        ]
        // {
          # Generate dynamic Hyprland plugins configuration
          "hypr/nix.conf" = {
            text =
              let
                # hy3 is already built against the correct hyprland from the flake
                hy3-plugin = hy3.packages.${pkgs.stdenv.hostPlatform.system}.hy3;
              in
              ''
              # Nix Generated
              # Cursor — single source of truth: constants.theme.cursor/cursorSize.
              # Mirrored by HM home.sessionVariables and (on NixOS) by
              # environment.sessionVariables, but those don't propagate into
              # Hyprland's process tree under non-NixOS session managers (SDDM
              # on Ubuntu doesn't source hm-session-vars.sh), so we set them
              # via Hyprland's own env= directive here too.
              env = XCURSOR_THEME,${constants.theme.cursor}
              env = XCURSOR_SIZE,${toString constants.theme.cursorSize}
              ${lib.optionalString systemInfo.hasNvidia ''
              # Additional ENV VARS
              env = __GLX_VENDOR_LIBRARY_NAME,nvidia
              env = LIBVA_DRIVER_NAME,nvidia
              env = MOZ_DISABLE_RDD_SANDBOX,1
              env = NVD_BACKEND,direct
              ''}
              # Plugins
              plugin = ${hy3-plugin}/lib/libhy3.so
              '';
          };
        };
    };
}
