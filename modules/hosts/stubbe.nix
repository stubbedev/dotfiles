{ config, inputs, ... }:
let
  hm = config.flake.modules.homeManager;
  hmLinux = config.linuxOnlyHomeModules or { };
in
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports =
        builtins.attrValues hm
        ++ builtins.attrValues hmLinux
        ++ [ inputs.nixvim.homeModules.nixvim ];
    };
  };
}
