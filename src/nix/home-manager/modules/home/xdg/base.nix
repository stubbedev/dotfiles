{ ... }:
{
  flake.modules.homeManager.xdgBase = { homeLib, lib, config, ... }:
    lib.mkIf config.features.desktop {
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
      ];
    };
}
