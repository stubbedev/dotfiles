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
      systemInfo = import (self + "/lib/system-info.nix") { inherit pkgs; };
      homeLib = import (self + "/lib.nix") { inherit lib pkgs systemInfo self; };
    in
    {
      _module.args = {
        inherit
          constants
          systemInfo
          homeLib
          self
          ;
        inherit (inputs) hyprland hy3 fenix opencode srv;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
        "tree-sitter" = inputs."tree-sitter";
      };
    };
}
