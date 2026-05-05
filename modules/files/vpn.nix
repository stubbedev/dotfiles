_: {
  flake.modules.homeManager.filesVpn =
    {
      self,
      lib,
      config,
      homeLib,
      ...
    }:
    let
      # Build the four scripts for one VPN provider as Nix bins under
      # ~/.nix-profile/bin/vpn-<provider>-{connect,disconnect,status,waybar}.
      # The provider name is baked into each script via @PROVIDER_NAME@
      # substitution; runtime config (gateway, username, password) is
      # decrypted by sops-nix into ~/.config/vpn/<provider>/.
      mkVpnScripts =
        provider:
        map
          (
            action:
            homeLib.mkScriptBin {
              name = "vpn-${provider}-${action}";
              source = "src/vpn/${provider}/${action}.sh";
              vars.PROVIDER_NAME = provider;
            }
          )
          [
            "connect"
            "disconnect"
            "status"
            "waybar"
          ];
    in
    lib.mkIf config.features.vpn {
      # Two binary-mode secrets per provider: the VPN gateway/username
      # config (rotates rarely, edited via `hm secret edit vpn-konform-config`)
      # and the password (rotates often, edited via `hm secret set
      # vpn-konform`). Both decrypt to ~/.config/vpn/konform/, which the
      # connect/waybar scripts source/read at runtime.
      sops.secrets.vpn-konform-config = {
        sopsFile = self + "/secrets/vpn-konform-config";
        format = "binary";
        path = "${config.home.homeDirectory}/.config/vpn/konform/config";
      };
      sops.secrets.vpn-konform = {
        sopsFile = self + "/secrets/vpn-konform";
        format = "binary";
        path = "${config.home.homeDirectory}/.config/vpn/konform/password";
      };

      home.packages = mkVpnScripts "konform";
    };
}
