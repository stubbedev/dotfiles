{ config, ... }:
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module.imports = builtins.attrValues config.flake.modules.homeManager;
  };
}
