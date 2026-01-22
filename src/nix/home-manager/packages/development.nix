{ pkgs, config, ... }:
let inherit (config.lib.nixGL) wrap;
in with pkgs; [
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
  (wrap jetbrains-toolbox)
  gpclient
]

