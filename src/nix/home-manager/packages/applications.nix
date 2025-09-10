# Desktop applications with GUI
# Applications that require graphical interface and nixGL wrapping
{ pkgs, config, ... }:
with pkgs; [
  # Database management
  (config.lib.nixGL.wrap mongodb-compass)

  # Terminal emulator
  (config.lib.nixGL.wrap alacritty)

  # Commented out applications (uncomment as needed)
  # (config.lib.nixGL.wrap ghostty)       # Alternative terminal
  # (config.lib.nixGL.wrap mailspring)    # Email client
  # (config.lib.nixGL.wrap dbeaver-bin)   # Database client
]

