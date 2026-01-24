{ pkgs, homeLib, ... }:
with pkgs; [
  # JavaScript/TypeScript runtimes (CLI tools)
  nodejs
  bun
  yarn
  deno
  volta

  # Go tools (CLI)
  gopass
  gotools
  air
  templ

  # Database tools (CLI)
  mongodb-tools
  mongosh

  # PHP tools (CLI)
  mago

  # IDE toolbox (GUI app)
  (homeLib.gfx jetbrains-toolbox)
  networkmanager-openconnect
  openconnect
]
