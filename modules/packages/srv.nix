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
      home.packages = [
        srv.packages.${system}.srv
        pkgs.mkcert
        # certutil — used by mkcert to install the root CA into Firefox/
        # Chromium NSS databases.
        pkgs.nss.tools
      ];
    };
}
