{ config, ... }:
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues config.flake.modules.homeManager;
      # Publishes laptop.local; stubbe.lib.lanHosts (modules/core/lib) is the
      # catalogue every host generates its ssh aliases from.
      host = {
        mdnsName = "laptop";
        battery = true;
      };
    };
  };
}
