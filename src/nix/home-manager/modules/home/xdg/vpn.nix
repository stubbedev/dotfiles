{ ... }:
{
  flake.modules.homeManager.xdgVpn = { vpnConfigs, lib, config, ... }:
    lib.mkIf config.features.vpn {
      xdg.configFile = vpnConfigs;
    };
}
