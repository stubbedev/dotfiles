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
          # Hyprland 0.55+ Lua config. Compositor config lives in hyprland.lua;
          # it require()s the Nix-generated nix.lua below for dynamic values.
          "hypr/hyprland.lua"
          # Ecosystem daemons still use hyprlang (no Lua support).
          "hypr/hypridle.conf"
          "hypr/hyprlock.conf"
          "hypr/hyprpaper.conf"
          "hypr/hyprsunset.conf"
          "hypr/hyprtoolkit.conf"
          # Catppuccin color vars (hyprlang $vars). The compositor uses Lua
          # locals now, but hyprlock.conf + hyprlock.launch.sh still source
          # this hyprlang file, so it must stay deployed.
          "hypr/theme.conf"
          "hypr/scripts"
        ]
        // {
          # Dynamic, Nix-derived bits required() by hyprland.lua: cursor/NVIDIA
          # env and the hy3 plugin path (a /nix/store path only Nix knows).
          "hypr/nix.lua" = {
            text =
              let
                # hy3 is already built against the correct hyprland from the flake
                hy3-plugin = hy3.packages.${pkgs.stdenv.hostPlatform.system}.hy3;
              in
              ''
              -- Nix Generated
              -- Cursor — single source of truth: constants.theme.cursor/cursorSize.
              -- Mirrored by HM home.sessionVariables and (on NixOS) by
              -- environment.sessionVariables, but those don't propagate into
              -- Hyprland's process tree under non-NixOS session managers (SDDM
              -- on Ubuntu doesn't source hm-session-vars.sh), so we set them
              -- via Hyprland's own hl.env here too.
              hl.env("XCURSOR_THEME", "${constants.theme.cursor}")
              hl.env("XCURSOR_SIZE", "${toString constants.theme.cursorSize}")
              ${lib.optionalString systemInfo.hasNvidia ''
              -- Additional ENV VARS
              hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
              hl.env("LIBVA_DRIVER_NAME", "nvidia")
              hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
              hl.env("NVD_BACKEND", "direct")
              ''}
              -- Plugins
              hl.plugin.load("${hy3-plugin}/lib/libhy3.so")
              '';
          };
        };
    };
}
