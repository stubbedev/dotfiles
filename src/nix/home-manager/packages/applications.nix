{ pkgs, config, ... }:
with pkgs; [
  (config.lib.nixGL.wrap mongodb-compass)
  (config.lib.nixGL.wrap alacritty)

  # Commented out applications (uncomment as needed)
  # (config.lib.nixGL.wrap ghostty)       # Alternative terminal
  # (config.lib.nixGL.wrap mailspring)    # Email client
  # (config.lib.nixGL.wrap dbeaver-bin)   # Database client
]

