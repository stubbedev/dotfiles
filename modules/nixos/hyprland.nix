{ inputs, ... }:
{
  flake.modules.nixos.hyprland =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.hyprland or false) {
      programs.hyprland = {
        enable = true;
        # Pin to the same v0.54.2 input the HM wrappers use (flake.nix:17),
        # so HM and NixOS agree on the Hyprland binary version.
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      };
    };
}
