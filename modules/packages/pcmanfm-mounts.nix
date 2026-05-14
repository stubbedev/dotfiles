_: {
  flake.modules.homeManager.pcmanfmMounts =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    # gvfs + udisks2 are user-installed only on non-NixOS hosts; on NixOS
    # they come from services.{gvfs,udisks2}.enable (modules/nixos/storage.nix).
    lib.mkIf (config.features.desktop && config.host.platform != "nixos") {
      home.packages = with pkgs; [
        gvfs
        udisks2
      ];
    };
}
