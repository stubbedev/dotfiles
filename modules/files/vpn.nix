_: {
  flake.modules.homeManager.filesVpn =
    {
      vpnScripts,
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.vpn {
      home.file = {
        ".local/bin/konform-vpn-waybar" = {
          source = self + "/src/vpn/konform/waybar.sh";
          executable = true;
        };
      }
      // vpnScripts;
    };
}
