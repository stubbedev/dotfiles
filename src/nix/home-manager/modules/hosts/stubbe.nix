{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues hm;

      features = {
        desktop = true;
        development = true;
        hyprland = true;
        theming = true;
        media = true;
        vpn = true;
        opencode = true;
        greetd = true;
      };
    };
  };
}
