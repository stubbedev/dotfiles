{ pkgs, config, ... }:
with pkgs; [
  mongodb-compass
  alacritty

  # Commented out applications (uncomment as needed)
  # ghostty       # Alternative terminal
  # mailspring    # Email client
  # dbeaver-bin   # Database client
]

