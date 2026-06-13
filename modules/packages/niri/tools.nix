_: {
  linuxOnlyHomeModules.packagesNiriTools =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.niri {
      home.packages =
        with pkgs;
        # awww is the niri wallpaper daemon — dropped once wayle (which renders
        # wallpaper itself) takes over. ships two binaries (awww + awww-daemon),
        # wrap each so both land in the profile; lib.getExe alone drops the daemon.
        lib.optionals (!config.features.wayle) [
          (homeLib.gfx awww)
          (homeLib.gfxExe "awww-daemon" awww)
        ]
        ++ [
          xwayland-satellite
        ];
    };
}
