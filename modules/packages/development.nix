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
        # mkWrappedPackage (not bare gfx): keeps neovide.desktop + icons on
        # XDG_DATA_DIRS so it shows in rofi on non-NixOS (bare gfx emits only
        # the nixGL bin). See modules/packages/media.nix for the full rationale.
        (homeLib.mkWrappedPackage { pkg = neovide; })

        # Go tools (CLI)
        gopass
        gotools
        air
        templ

        # Database tools (CLI)
        mongodb-tools
        mongosh
        redis # provides redis-cli

        # c3
        c3c

        # Caddy server
        caddy

        # RDP client
        freerdp

        # IDE toolbox (GUI app)
        # mkWrappedPackage (not bare gfx): keeps jetbrains-toolbox.desktop on
        # XDG_DATA_DIRS so it shows in rofi on non-NixOS.
        (homeLib.mkWrappedPackage { pkg = jetbrains-toolbox; })
        openconnect

        # Native/Rust build perf — fast linker + rustc wrapper.
        # Used by repos whose `.cargo/config.toml` wires
        # `linker = "clang"` + `-fuse-ld=mold`, and by `RUSTC_WRAPPER=sccache`.
        mold
        (lib.setPrio 15 clang)
        sccache
        cargo-sweep
      ];
    };
}
