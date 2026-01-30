{ inputs, ... }:
{
  flake.modules.homeManager.context = { config, lib, pkgs, ... }:
    let
      constants = import ../../constants.nix { inherit config; };

      systemInfo = import ../../lib/system-info.nix { inherit lib pkgs; };

      homeLib = import ../../lib.nix { inherit lib pkgs systemInfo; };

      # Load VPN scripts/config dynamically
      vpnConfigs =
        if config.features.vpn then
          homeLib.loadVpnConfigs ../../../../vpn
        else
          { };
      vpnScripts =
        if config.features.vpn then
          homeLib.loadVpnScripts ../../../../vpn
        else
          { };
    in
    {
      _module.args = {
        inherit constants systemInfo homeLib vpnConfigs vpnScripts;
        inherit (inputs) hyprland hy3;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
      };
    };
}
