_: {
  flake.modules.homeManager.programsFenix =
    {
      lib,
      config,
      pkgs,
      fenix,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    lib.mkIf config.features.rust {
      home.packages = [
        fenix.packages.${system}.latest.toolchain
      ];
    };
}
