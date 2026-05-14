{ self, ... }:
{
  flake.modules.homeManager.nix =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cache = import (self + "/lib/nix-cache.nix");
    in
    {
      programs.home-manager.enable = true;

      # Daemon-level substituters live in modules/nixos/nix-settings.nix
      # on NixOS hosts (useGlobalPkgs makes HM read those same overlaid
      # pkgs, and only the daemon's substituters actually fetch). On
      # standalone HM we set them here so user-mode `nix` calls hit the
      # same caches.
      nix = lib.mkIf (config.host.platform != "nixos") {
        package = lib.mkDefault pkgs.nix;
        settings = {
          inherit (cache) substituters trusted-public-keys;
        };
      };
    };
}
