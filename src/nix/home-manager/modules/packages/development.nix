{ ... }:
{
  flake.modules.homeManager.packages.development = { pkgs, homeLib, ... }: {
    home.packages = with pkgs; [
      # JavaScript/TypeScript runtimes (CLI tools)
      nodejs
      bun
      yarn
      deno
      volta

      # Editor and Lua runtimes
      neovim
      lua5_1
      luajit

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
    ];
  };
}
