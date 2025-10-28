# Hyprland compositor and related tools
{ pkgs, config, ... }:
let
  enableHyprland = builtins.getEnv "USE_HYPRLAND";
  useHyprland = enableHyprland == "true";
in
if useHyprland then
  with pkgs; [
  # Note: hyprland and hyprlock installed natively
  # (config.lib.nixGL.wrap hyprland)
  # hyprlock

  # Hyprland ecosystem
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
  hyprsysteminfo
  hyprwayland-scanner

  # Wayland tools
  wlprop
  wayland-scanner
  wayland-utils
  xwayland

  # Desktop components
  waybar
  ashell
  swaynotificationcenter
  rofi-wayland

  # Portals
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-wlr

  # Clipboard
  wl-clip-persist
]
else
  []
