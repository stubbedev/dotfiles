{ ... }:
{
  flake.modules.homeManager.targets = { pkgs, ... }: {
    targets.genericLinux = {
      enable = true;
      nixGL = { packages = pkgs.nixgl; };
    };
  };
}
