{ inputs, self, ... }:
{
  flake.modules.homeManager.context =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      constants = import (self + "/constants.nix") { inherit config; };

      systemInfo = import (self + "/lib/system-info.nix") { inherit lib pkgs; };

      homeLib = import (self + "/lib.nix") { inherit lib pkgs systemInfo self; };

      # Load VPN scripts/config dynamically
      vpnConfigs = if config.features.vpn then homeLib.loadVpnConfigs (self + "/src/vpn") else { };
      vpnScripts = if config.features.vpn then homeLib.loadVpnScripts (self + "/src/vpn") else { };
    in
    {
      _module.args = {
        inherit
          constants
          systemInfo
          homeLib
          vpnConfigs
          vpnScripts
          self
          ;
        inherit (inputs) hyprland hy3 fenix opencode srv;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
        "tree-sitter" = inputs."tree-sitter";
      };
    };
}
