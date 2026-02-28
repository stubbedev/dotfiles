_: {
  flake.modules.homeManager.programsCargo =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.rust {
      programs.cargo = {
        enable = true;
      };
    };
}
