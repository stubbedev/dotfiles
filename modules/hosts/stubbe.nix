{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues hm;
    };
  };
}
