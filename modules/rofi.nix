# rofi — the launcher, and the app/window/run switcher behind the Hyprland
# binds.
#
# Three files, split by who owns the values:
#   config.rasi            generated — it names the icon theme, which
#                          `pkgs.stubbe.theme` owns.
#   catppuccin-mocha.rasi  generated — it is the palette, nothing else.
#   catppuccin-default.rasi  a real file: pure layout, referencing the palette
#                          variables above by name.
_: {
  flake.modules.homeManager.rofi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.hyprland {
      home.packages = [ (config.stubbe.gfx.wrap pkgs.rofi) ];

      xdg.configFile = {
        "rofi/config.rasi".text = ''
          @import "catppuccin-mocha"
          configuration {
              matching:          "fuzzy";
              sort:              true;
              sorting-method:    "fzf";
              drun-match-fields: "name,generic,keywords";
              drun-show-actions: true;
              show-icons:        true;
              icon-theme:        "${pkgs.stubbe.theme.icon}";
              lines:             10;
          }
          @theme "catppuccin-default"
        '';

        # The palette as rasi variables, generated from pkgs.stubbe.colors —
        # catppuccin-default.rasi refers to these by name.
        "rofi/catppuccin-mocha.rasi".text = ''
          * {
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: hex: "  ${name}: #${hex};") pkgs.stubbe.colors
          )}
          }
        '';

        "rofi/catppuccin-default.rasi".source = pkgs.stubbe.file "src/rofi/catppuccin-default.rasi";
      };
    };
}
