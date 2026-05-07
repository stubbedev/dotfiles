{ inputs, ... }:
{
  flake.modules.nixos.lanzaboote =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Module imports must be unconditional — the option set has to
      # exist regardless of host.secureBoot, otherwise the mkIf'd config
      # below references options that aren't defined.
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      config = lib.mkIf config.host.secureBoot {
        # systemd-boot and lanzaboote are mutually exclusive; force off
        # the systemd-boot config from modules/nixos/hosts/stubbe-nixos.nix
        # whenever secureBoot is on.
        boot.loader.systemd-boot.enable = lib.mkForce false;

        boot.lanzaboote = {
          enable = true;
          # sbctl stores the platform key + KEK + DB keys here. Create
          # the bundle MANUALLY before flipping host.secureBoot on:
          #   sudo sbctl create-keys
          #   sudo sbctl enroll-keys --microsoft   # or --custom
          # Verify with `sudo sbctl status` (Setup Mode: Disabled,
          # Secure Boot: Enabled).
          pkiBundle = "/var/lib/sbctl";
        };

        # sbctl CLI for verifying + managing the key bundle on the
        # running system.
        environment.systemPackages = [ pkgs.sbctl ];
      };
    };
}
