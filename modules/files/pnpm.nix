_: {
  flake.modules.homeManager.filesPnpm =
    {
      config,
      lib,
      ...
    }:
    lib.mkIf config.features.development {
      # Two-layer defense against stale pnpm config:
      #
      # 1. xdg.configFile pins ~/.config/pnpm/rc to a known store-dir.
      #    `force = true` lets activation overwrite a pre-existing
      #    unmanaged file (e.g. a leftover from a dev container that
      #    mounted ~/.config/pnpm/ and ran `pnpm config set` inside).
      #    Without force, home-manager aborts with "Existing file ... in
      #    the way".
      #
      # 2. npm_config_store_dir env var. pnpm reads npm-style env vars
      #    and they outrank the rc file, so even if some tool writes a
      #    new bad value into rc between rebuilds, every shell still
      #    resolves to the right path.
      xdg.configFile."pnpm/rc" = {
        force = true;
        text = ''
          store-dir=${config.home.homeDirectory}/.local/share/pnpm/store
        '';
      };

      home.sessionVariables.npm_config_store_dir = "${config.home.homeDirectory}/.local/share/pnpm/store";
    };
}
