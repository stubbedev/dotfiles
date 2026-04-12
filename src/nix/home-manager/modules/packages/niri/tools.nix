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
        awww
        xwayland-satellite
      ];
    };
}
