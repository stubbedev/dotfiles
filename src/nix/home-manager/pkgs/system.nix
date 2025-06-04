{ pkgs, config }:

with pkgs;[
  (config.lib.nixGL.wrap hyprland)
  hyprlock
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
  hyprsysteminfo
  waybar
  swaynotificationcenter
  networkmanagerapplet
  blueman
  adwaita-icon-theme
  adwaita-fonts
  adwaita-qt
  adwaita-qt6
  rofi-wayland
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-wlr
  libsForQt5.layer-shell-qt
  clipman
  cliphist
  wl-clip-persist
  nerd-fonts.jetbrains-mono
  tela-circle-icon-theme
  xwayland
  whitesur-icon-theme
]
