_: {
  flake.modules.homeManager.filesPnpm =
    {
      config,
      lib,
      ...
    }:
    lib.mkIf config.features.development {
      # Pin ~/.config/pnpm/rc to a known store-dir. pnpm reads this rc on
      # its own, so no env var is needed.
      #
      # `force = true` lets activation overwrite a pre-existing unmanaged
      # file (e.g. a leftover from a dev container that mounted
      # ~/.config/pnpm/ and ran `pnpm config set` inside). Without force,
      # home-manager aborts with "Existing file ... in the way".
      #
      # Note: do NOT also export npm_config_store_dir as a session var —
      # npm scans every npm_config_* env var and has no `store-dir` key,
      # so it would print a deprecation warning on every npm invocation.
      xdg.configFile."pnpm/rc" = {
        force = true;
        text = ''
          store-dir=${config.home.homeDirectory}/.local/share/pnpm/store
        '';
      };
    };
}
