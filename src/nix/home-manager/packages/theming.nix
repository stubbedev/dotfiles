# Desktop theming and visual customization
# Fonts, icons, themes, and desktop appearance packages
{ pkgs, ... }:
with pkgs; [
  # Fonts
  nerd-fonts.jetbrains-mono
  adwaita-fonts

  # Icon themes
  adwaita-icon-theme
  vimix-icon-theme

  # GTK themes
  rose-pine-gtk-theme
  adwaita-qt
  adwaita-qt6

  # Desktop shell integration
  libsForQt5.layer-shell-qt
  gtk4-layer-shell
]

