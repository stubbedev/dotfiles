_: {
  # awww (the wallpaper daemon) now ships from modules/home/wayle.nix — wayle's
  # wallpaper engine drives it. This module only carries niri's other tools.
  linuxOnlyHomeModules.packagesNiriTools =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.niri {
      home.packages = [ pkgs.xwayland-satellite ];
    };
}
