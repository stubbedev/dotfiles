# btop, the system monitor.
#
# The theme is generated from `pkgs.stubbe.colors` (it used to be four
# hand-maintained .theme files, three of which were never selected), and
# btop.conf is installed writable because btop rewrites it as you change
# settings in the UI.
_: {
  flake.modules.homeManager.monitoring =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      c = pkgs.stubbe.withHash;

      themeName = "catppuccin-mocha";
      themePath = "${config.xdg.configHome}/btop/themes/${themeName}.theme";
    in
    lib.mkIf config.features.desktop {
      programs.btop = {
        enable = true;
        # Not a plain `pkgs.btop`: btop dlopens libnvidia-ml.so for its GPU
        # panel, and a dlopen by soname does not go through glvnd — so it needs
        # the driver libs on the loader path even on NixOS.
        package = gfx.withDriverLibs pkgs.btop;

        # btop reads themes but never writes them, so a store symlink is right
        # here. Generated, so the palette lives in exactly one place.
        themes.${themeName} = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value: ''theme[${key}]="${value}"'') {
            main_bg = c.base;
            main_fg = c.text;
            title = c.text;
            hi_fg = c.blue;
            selected_bg = c.surface1;
            selected_fg = c.blue;
            inactive_fg = c.overlay1;
            graph_text = c.rosewater;
            meter_bg = c.surface1;
            proc_misc = c.rosewater;
            cpu_box = c.mauve;
            mem_box = c.green;
            net_box = c.maroon;
            proc_box = c.blue;
            div_line = c.overlay0;
            temp_start = c.green;
            temp_mid = c.yellow;
            temp_end = c.red;
            cpu_start = c.teal;
            cpu_mid = c.sapphire;
            cpu_end = c.lavender;
            free_start = c.mauve;
            free_mid = c.lavender;
            free_end = c.blue;
            cached_start = c.sapphire;
            cached_mid = c.blue;
            cached_end = c.lavender;
            available_start = c.peach;
            available_mid = c.maroon;
            available_end = c.red;
            used_start = c.green;
            used_mid = c.teal;
            used_end = c.sky;
            download_start = c.peach;
            download_mid = c.maroon;
            download_end = c.red;
            upload_start = c.green;
            upload_mid = c.teal;
            upload_end = c.sky;
            process_start = c.sapphire;
            process_mid = c.lavender;
            process_end = c.mauve;
          }
        );
      };

      # btop rewrites btop.conf whenever a setting is changed in the UI, so it
      # cannot be a store symlink. @THEME@ is substituted rather than hardcoded:
      # the file used to carry a literal /home/stubbe path.
      stubbe.mutable.".config/btop/btop.conf" = {
        method = "copy";
        source = pkgs.stubbe.render "src/monitoring/btop.conf" { THEME = themePath; };
      };
    };
}
