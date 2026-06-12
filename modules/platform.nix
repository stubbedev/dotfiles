_: {
  flake.modules.homeManager.platform =
    { lib, ... }:
    {
      options.host.platform = lib.mkOption {
        type = lib.types.enum [
          "linux"
          "nixos"
        ];
        default = "linux";
        description = ''
          Host platform. "linux" means we're running home-manager on a
          non-NixOS distro (Fedora, Ubuntu, ...) — privileged activation
          scripts manage /etc/pam.d, udev rules, polkit, apparmor etc.
          "nixos" means the corresponding NixOS modules own those files
          and the privileged activations are gated off.
        '';
      };
    };

  flake.modules.nixos.platform =
    { lib, ... }:
    {
      options.host = {
        primaryUser = lib.mkOption {
          type = lib.types.str;
          default = "stubbe";
          description = ''
            Username of the host's primary user. NixOS modules read this to
            locate the matching home-manager.users.<name> entry, so they can
            ask "did the host enable features.docker?" and add the user to
            the docker group accordingly. The flake assumes every NixOS host
            has exactly one HM-managed primary user.
          '';
        };

        installed = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Set to true on hosts that target real, post-install hardware
            (e.g. `stubbe-nixos`). Activates modules/nixos/filesystems.nix
            (the real btrfs layout) and inhibits any stub fileSystems that
            exist purely to keep a fresh checkout `nix build`-evaluable.
            The installer ISO leaves this at the default (false) so the
            live image keeps using the cd-dvd installation media's own
            root mount.
          '';
        };

        secureBoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Replace systemd-boot with lanzaboote (signed bootloader for
            UEFI Secure Boot). DEFAULT FALSE: enabling without enrolling
            Secure Boot keys (sbctl create-keys + sbctl enroll-keys) will
            brick boot. Recommended flow:
              1. Install with secureBoot = false; first-boot to verify.
              2. Run `sudo sbctl create-keys` then `sudo sbctl enroll-keys
                 --microsoft` (or --custom) once firmware is in setup mode.
              3. Flip this flag to true; rebuild; reboot.
          '';
        };

        impermanent = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Wipe the root subvolume on every boot, persisting only
            declared paths under /persist. DEFAULT FALSE: enabling on a
            system that hasn't been laid out for impermanence will lose
            state. Recommended flow:
              1. Install with impermanent = false; the install script
                 creates an @-blank snapshot of the empty @ subvol so the
                 flag is safe to flip later.
              2. Audit modules/nixos/impermanence.nix's persistence list;
                 add anything host-specific.
              3. Flip this flag to true; rebuild; reboot.
          '';
        };
      };
    };
}
