_: {
  linuxOnlyHomeModules.pcmanfmMounts =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf (config.features.desktop && config.host.platform != "nixos") {
      home.packages = with pkgs; [
        gvfs
        udisks2
      ];
    };
}
