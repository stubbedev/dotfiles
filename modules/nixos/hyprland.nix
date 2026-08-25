_: {
  flake.modules.nixos.hyprland =
    {
      config,
      lib,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.hyprland or false) {
      # package defaults to pkgs.hyprland — the same one the HM wrappers wrap,
      # so HM and NixOS agree on the binary without pinning it here.
      programs.hyprland.enable = true;
    };
}
