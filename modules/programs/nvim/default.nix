{ inputs, ... }:
{
  flake.modules.homeManager.programsNvim =
    { lib, config, pkgs, ... }:
    lib.mkIf config.features.desktop {
      home.packages = [
        (inputs.wrappers.lib.evalPackage [
          { inherit pkgs; }
          (import ./_wrapper.nix)
        ])
      ];
    };
}
