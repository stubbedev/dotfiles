{ pkgs, ... }:
with pkgs; [
  nodejs
  bun
  yarn
  deno
  volta
  zig
  rustup
  gopass
  gotools
  air
  templ
  mongodb-tools
  mago
  #jetbrains.phpstorm
  #jetbrains.webstorm
  #jetbrains.pycharm-community-bin
]

