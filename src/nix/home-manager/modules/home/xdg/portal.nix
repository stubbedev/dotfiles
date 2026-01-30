{ ... }:
{
  flake.modules.homeManager.xdgPortal = { homeLib, ... }: {
    xdg.configFile = homeLib.xdgSources [
      "xdg-desktop-portal/portals.conf"
    ];
  };
}
