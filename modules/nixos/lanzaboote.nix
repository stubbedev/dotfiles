{ inputs, ... }:
{
  flake.modules.nixos.lanzaboote =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.host.secureBoot {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      # systemd-boot and lanzaboote are mutually exclusive; force off
      # the systemd-boot config from modules/nixos/hosts/stubbe-nixos.nix
      # whenever secureBoot is on.
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote = {
        enable = true;
        # sbctl stores the platform key + KEK + DB keys here. The key
        # bundle must be created MANUALLY before flipping host.secureBoot
        # on, otherwise the post-build hook can't sign anything:
        #   sudo sbctl create-keys
        #   sudo sbctl enroll-keys --microsoft   # or --custom
        # Verify with `sudo sbctl status` (Setup Mode: Disabled,
        # Secure Boot: Enabled).
        pkiBundle = "/var/lib/sbctl";
      };

      # sbctl CLI for verifying and managing the key bundle from the
      # running system.
      environment.systemPackages = [ pkgs.sbctl ];
    };
}
