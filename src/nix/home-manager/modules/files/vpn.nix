{ ... }:
{
  flake.modules.homeManager.filesVpn = { vpnScripts, lib, config, ... }:
    lib.mkIf config.features.vpn {
      home.file = {
        ".local/bin/konform-vpn-waybar" = {
          source = ../../../../vpn/konform/waybar.sh;
          executable = true;
        };
      } // vpnScripts;
    };
}
