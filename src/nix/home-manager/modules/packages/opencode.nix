_: {
  flake.modules.homeManager.packagesOpencode =
    {
      pkgs,
      lib,
      config,
      opencode,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    lib.mkIf config.features.opencode {
      home.packages = [ opencode.packages.${system}.opencode ];
    };
}
