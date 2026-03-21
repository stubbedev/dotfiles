_: {
  flake.modules.homeManager.packagesDevelopment =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      luaBin = pkgs.writeShellScriptBin "lua" ''
        exec ${pkgs.lua5_1}/bin/lua "$@"
      '';
      luajitBin = pkgs.writeShellScriptBin "luajit" ''
        exec ${pkgs.luajit}/bin/luajit "$@"
      '';
    in
    lib.mkIf config.features.development {
      home.packages = with pkgs; [
        # JavaScript/TypeScript runtimes (CLI tools)
        nodejs
        bun
        yarn
        deno
        volta

        # Only wanted for Oauth handshake
        claude-code

        # Editor and Lua runtimes
        neovim
        luaBin
        luajitBin

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

        # c3
        c3c

        # IDE toolbox (GUI app)
        (homeLib.gfx jetbrains-toolbox)
        networkmanager-openconnect
        openconnect
      ];
    };
}
