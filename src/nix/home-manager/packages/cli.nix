# Core CLI utilities and build tools
{ pkgs, ... }:
with pkgs; [
  # Shell and terminal
  bc
  zsh
  tmux
  starship

  # Modern CLI replacements
  fd
  eza
  bat
  fzf
  ripgrep
  tree-sitter
  zoxide

  # System monitoring
  htop
  btop

  # Network utilities
  curl
  wget

  # Data processing
  jq
  jless

  # Text processing
  gnugrep
  hunspell
  gawk

  # Version control
  git
  lazygit
  lazydocker
  gh

  # Archive handling
  zip
  unzip
  p7zip

  # System utilities
  xsel
  less
  more

  # Build essentials
  gcc
  gnumake
  gnutar
  coreutils
  cmake
  pkg-config
  gettext
  libtool
  autoconf
  automake

  # Terminal file manager
  tabiew
]
