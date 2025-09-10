# Nix ecosystem tools and system utilities
# Tools specifically for Nix/NixOS management and system administration
{ pkgs, ... }:
with pkgs; [
  # Nix tools
  nh # Nix helper
  nix-zsh-completions # Zsh completions for Nix

  # Container management
  lazydocker # Docker TUI

  # Security and secrets
  pass # Password store

  # Data visualization
  tabiew # CSV/data viewer

  # Pagers
  less
  more
]

