{ ... }:
{
  flake.modules.homeManager.xdgVpn = { vpnConfigs, ... }: {
    xdg.configFile = vpnConfigs;
  };
}
