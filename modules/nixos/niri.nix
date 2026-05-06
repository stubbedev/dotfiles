_: {
  flake.modules.nixos.niri =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.niri or false) {
      programs.niri.enable = true;
    };
}
