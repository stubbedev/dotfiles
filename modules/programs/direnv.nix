_: {
  flake.modules.homeManager.programsDirenv =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.development {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };
}
