# Core command-line tools and shell utilities
# Essential CLI tools that form the foundation of the terminal experience
{ pkgs, ... }:
with pkgs; [
  # Shell and terminal
  zsh
  tmux
  neovim

  # File operations
  fd # Modern find replacement
  eza # Modern ls replacement
  bat # Cat with syntax highlighting
  fzf # Fuzzy finder
  ripgrep # Fast grep replacement
  tree-sitter # Parsing toolkit

  # System monitoring
  htop # Process viewer
  btop # Modern system monitor

  # Network tools
  curl
  wget

  # Text processing
  jq # JSON processor
  jless # JSON pager
  gnugrep # GNU grep
  hunspell # Spell checker

  # Version control
  git
  lazygit # Git TUI
  gh # GitHub CLI

  # Archive tools
  zip
  unzip
  p7zip

  # Clipboard
  xsel
]

