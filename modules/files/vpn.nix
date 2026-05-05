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
      # Decrypted at activation to ~/.config/vpn/konform/password (mode 0400).
      # connect.sh and waybar.sh read this file directly — no shell wrapper.
      sops.secrets.vpn-konform = {
        sopsFile = self + "/secrets/vpn-konform";
        format = "binary";
        path = "${config.home.homeDirectory}/.config/vpn/konform/password";
      };

      home.file = {
        ".local/bin/konform-vpn-waybar" = {
          source = self + "/src/vpn/konform/waybar.sh";
          executable = true;
        };
      }
      // vpnScripts;
    };
}
