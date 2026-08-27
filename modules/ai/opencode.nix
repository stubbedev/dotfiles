# opencode CLI.
_: {
  flake.modules.homeManager.opencode =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.opencode {
      home.packages = [
        pkgs.opencode
      ];
    };
}
