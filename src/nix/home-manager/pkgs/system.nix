{ pkgs, config }:

with pkgs;[
  (config.lib.nixGL.wrap hyprland)
  (config.lib.nixGL.wrap hyprlock)
  networkmanagerapplet
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
  whitesur-icon-theme
]
