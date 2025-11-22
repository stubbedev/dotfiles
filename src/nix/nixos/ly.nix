# Ly display manager configuration
{ config, ... }:

{
  services.displayManager.ly = {
    enable = true;
    settings = {
      # Auto login configuration
      auto_login_user = "stubbe";
      auto_login_session = "Hyprland";

      # Disable vi mode
      vi_mode = false;

      # Disable background animation
      animation = "none";

      # Catppuccin Mocha theme colors
      # Colors in 0xSSRRGGBB format (SS = styling, RRGGBB = color)
      bg = "0x001e1e2e";        # Base background
      fg = "0x00cdd6f4";        # Base foreground
      error_fg = "0x01f38ba8";  # Red error text (bold)
      border_fg = "0x00bac2de"; # Subtext0 for borders
      # Additional colors can be added as needed
    };
  };
}