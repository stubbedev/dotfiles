# Development tools and programming languages
# Tools for software development, programming languages, and related utilities
{ pkgs, ... }:
with pkgs; [
  # JavaScript/Node.js ecosystem
  nodejs
  bun
  yarn
  deno
  volta # Node version manager

  # Systems programming
  zig
  rustup # Rust toolchain

  # Go tools
  gopass # Password manager
  gotools # Go development tools
  air # Go live reload
  templ # Go templating

  # Database tools
  mongodb-tools

  # Development environments
  jetbrains.phpstorm
  jetbrains.pycharm-community-bin
]

