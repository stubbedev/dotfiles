_: {
  flake.modules.homeManager.packagesOpencode =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.opencode {
      home.packages = [ pkgs.opencode ];
    };
}
