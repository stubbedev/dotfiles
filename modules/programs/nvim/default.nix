{ inputs, ... }:
{
  flake.modules.homeManager.programsNvim =
    { lib, config, pkgs, ... }:
    lib.mkIf config.features.desktop (
      let
        nvim = inputs.wrappers.lib.evalPackage [
          { inherit pkgs; }
          (import ./_wrapper.nix)
        ];
      in
      {
        home.packages = [ nvim ];
        home.sessionVariables = {
          EDITOR = lib.getExe nvim;
          VISUAL = lib.getExe nvim;
        };
      }
    );
}
