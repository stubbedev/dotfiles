_: {
  flake.modules.nixos.mkcert =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      userHome = config.users.users.${config.host.primaryUser}.home;
      rootCA = "${userHome}/.local/share/mkcert/rootCA.pem";
    in
    lib.mkIf (hmFeatures.srv or false) {
      environment.systemPackages = [
        pkgs.mkcert
        # certutil — used by mkcert to install the root CA into Firefox/
        # Chromium NSS databases.
        pkgs.nss.tools
      ];

      # builtins.path imports the cert into the store so nss-cacert can
      # read it from inside the build sandbox; a raw "/home/..." string
      # would resolve at eval time but be unreadable at build time.
      security.pki.certificateFiles = lib.optional (builtins.pathExists rootCA) (
        builtins.path {
          path = rootCA;
          name = "mkcert-rootCA.pem";
        }
      );
    };
}
