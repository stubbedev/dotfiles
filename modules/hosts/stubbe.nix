{ config, ... }:
let
  hm = config.flake.modules.homeManager;
  hmLinux = config.linuxOnlyHomeModules or { };
in
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues hm ++ builtins.attrValues hmLinux;

      features = {
        desktop = true;
        development = true;
        hyprland = true;
        theming = true;
        media = true;
        vpn = true;
        opencode = true;
        srv = true;
        php = false;
        k8s = true;
        claudeCode = true;
        slack = true;
      };
    };
  };
}
