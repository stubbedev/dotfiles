_: {
  flake.modules.homeManager.packagesNiriTools =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.niri {
      home.packages = with pkgs; [
        # awww ships two binaries (awww + awww-daemon) — wrap each so both
        # land in the home-manager profile; lib.getExe alone would drop the daemon.
        (homeLib.gfx awww)
        (homeLib.gfxExe "awww-daemon" awww)
        xwayland-satellite
      ];
    };
}
