{ pkgs, config, ... }:
with pkgs; [
  # (config.lib.nixGL.wrap hyprland) # installed natively
  # hyprlock # installed natively
  hyprshot
  hyprlang
  hyprkeys
  hypridle
  hyprpaper
  hyprsunset
  hyprpicker
  hyprcursor
  hyprpolkitagent
  hyprutils
  hyprprop
  wlprop
  hyprsysteminfo
  hyprwayland-scanner
  wayland-scanner
  wayland-utils
  xwayland
  waybar
  swaynotificationcenter
  rofi-wayland
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-wlr
  wl-clip-persist
]
