{ config, ... }:
{
  configurations.nixos.desktop = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues config.flake.modules.nixos;

      networking.hostName = "stubbe-nixos";
      system.stateVersion = "26.05";

      host = {
        installed = true;
        graphicsNvidia = true;
      };
    };
  };
}
