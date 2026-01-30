{ ... }:
{
  flake.modules.homeManager.xdgPortal = { homeLib, lib, config, ... }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
      "xdg-desktop-portal/portals.conf"
      ];
    };
}
