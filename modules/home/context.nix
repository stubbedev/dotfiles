{ inputs, self, ... }:
{
  flake.modules.homeManager.homeContext =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      constants = import (self + "/constants.nix") { inherit config; };
      systemInfo = import (self + "/lib/system-info.nix") { inherit pkgs; };
      homeLib = import (self + "/lib.nix") {
        inherit
          lib
          pkgs
          systemInfo
          self
          ;
        isNixOS = config.host.platform == "nixos";
      };
    in
    {
      _module.args = {
        inherit
          constants
          systemInfo
          homeLib
          self
          ;
        inherit (inputs)
          fenix
          srv
          treeman
          ;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
        # Pinned zsh plugin sources (flake = false) consumed by
        # lib/zsh-packages.nix.
        inherit (inputs)
          zsh-vim-mode
          zsh-fzf-artisan
          zsh-fzf-npm-run
          ;
      };
    };
}
