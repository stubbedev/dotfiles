{ inputs, ... }:
{
  flake.modules.nixos.secureBoot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      config = lib.mkIf config.host.secureBoot {
        boot.loader.systemd-boot.enable = lib.mkForce false;

        boot.lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
        };

        environment.systemPackages = [ pkgs.sbctl ];
      };
    };
}
