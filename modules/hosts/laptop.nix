{ config, ... }:
{
  configurations.nixos.laptop = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues config.flake.modules.nixos;

      networking.hostName = "staggio";
      system.stateVersion = "26.11";

      host = {
        installed = true;
        battery = true;
        wifiInterface = "wlp0s20f3";
        luks = true;
        impermanent = true;
        hibernateSwapSize = 32;
      };

      services = {
        fprintd.enable = true;
        hardware.bolt.enable = true;
      };
    };
  };
}
