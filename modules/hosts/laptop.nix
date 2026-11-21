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
        browser = "chrome";
        luks = true;
        hibernateSwapSize = 32;
      };

      services = {
        fprintd.enable = true;
        hardware.bolt.enable = true;
      };
    };
  };
}
