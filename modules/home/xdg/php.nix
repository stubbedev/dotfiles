_: {
  flake.modules.homeManager.homeXdgPhp =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.php {
      xdg.configFile = homeLib.xdgSources [
        "php/php-fpm.conf"
      ];
    };
}
