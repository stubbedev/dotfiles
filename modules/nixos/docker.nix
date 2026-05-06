_: {
  flake.modules.nixos.docker =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.docker or false) {
      virtualisation.docker.enable = true;

      # Replaces the user-group-add step from the non-NixOS
      # modules/activation/_privileged/setup-docker.nix activation script.
      users.users.${config.host.primaryUser}.extraGroups = [ "docker" ];
    };
}
