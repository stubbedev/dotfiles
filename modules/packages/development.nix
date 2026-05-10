_: {
  flake.modules.homeManager.packagesDevelopment =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.development {
      home.packages = with pkgs; [
        # JavaScript/TypeScript runtimes (CLI tools)
        nodejs
        bun
        pnpm
        yarn
        deno

        # JS/TS formatters and linters (replaces former `bun add --global …`)
        prettier
        oxlint
        oxfmt
        stylua

        # Editor (nvim provided via the wrapper module).
        (homeLib.gfx neovide)

        # Go tools (CLI)
        gopass
        gotools
        air
        templ

        # Database tools (CLI)
        mongodb-tools
        mongosh

        # c3
        c3c

        # Caddy server
        caddy

        # IDE toolbox (GUI app)
        (homeLib.gfx jetbrains-toolbox)
        networkmanager-openconnect
        openconnect
      ];
    };
}
