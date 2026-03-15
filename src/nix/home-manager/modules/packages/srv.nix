_: {
  flake.modules.homeManager.packagesSrv =
    {
      pkgs,
      lib,
      config,
      srv,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    lib.mkIf config.features.srv {
      home.packages = [ srv.packages.${system}.srv ];
    };
}
