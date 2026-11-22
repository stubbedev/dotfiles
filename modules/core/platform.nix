{ config, ... }:
let
  inherit (config.stubbe.lib) userName;

  sharedOptions = lib: {
    flakeAttr = lib.mkOption {
      type = lib.types.str;
      description = ''
        The attribute this machine's configuration is defined under.
        modules/core/configurations.nix sets it from the attribute name.
      '';
    };

    graphicsNvidia = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The machine's display GPU is NVIDIA. The one GPU decision a host
        makes; modules/graphics.nix selects the nvidia driver stack from it.
      '';
    };

    battery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "The machine runs on a battery, so the desktop shell shows its charge.";
    };

    sleepVerb = lib.mkOption {
      type = lib.types.enum [
        "suspend"
        "suspend-then-hibernate"
      ];
      default = "suspend";
      description = ''
        The systemctl verb every "suspend" on this machine runs: the power
        menu, the idle timeout and logind's lid switch. A NixOS host with a
        hibernation swapfile defaults it to suspend-then-hibernate, so a
        machine left asleep hibernates after systemd's HibernateDelaySec.
      '';
    };

    browser = lib.mkOption {
      type = lib.types.enum [
        "firefox"
        "chrome"
      ];
      default = "firefox";
      description = ''
        The default web browser: the handler for http(s) links and HTML
        files, set by modules/desktop.nix in both the system and user MIME
        defaults.
      '';
    };

    emulatedSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "aarch64-linux" ];
      description = ''
        Systems this machine builds for machines that cannot build them
        themselves. On a NixOS host modules/nix.nix registers them with
        binfmt_misc, which also adds them to the nix daemon's
        `extra-platforms`, so it can serve as the remote builder of a host
        whose cached closure is not there yet.
      '';
    };
  };
in
{
  flake.modules.homeManager.platform =
    { lib, ... }:
    {
      options.host = sharedOptions lib // {
        platform = lib.mkOption {
          type = lib.types.enum [
            "nixos"
            "android"
          ];
          description = ''
            Host platform. "nixos" means home-manager runs inside a NixOS
            host, whose matching NixOS module owns every system-level file.
            "android" means nix-on-droid inside Termux: a proot'd glibc
            environment with no init, no D-Bus, no /etc and no /usr. phix
            runs the systemd user units there instead (`phix service`), so
            user services and timers are declared the same way on both.
          '';
        };

        profile = lib.mkOption {
          type = lib.types.enum [
            "workstation"
            "mobile"
          ];
          default = "workstation";
          description = ''
            What the machine is for. Every `features.*` flag defaults from it
            (modules/core/features.nix): "workstation" is the full desktop and
            development set, "mobile" a terminal-only set for a phone.
          '';
        };
      };
    };

  flake.modules.nixos.platform =
    { config, lib, ... }:
    {
      config.host.sleepVerb = lib.mkIf (config.host.hibernateSwapSize != null) (
        lib.mkDefault "suspend-then-hibernate"
      );

      options.host = sharedOptions lib // {
        sharedFacts = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          readOnly = true;
          default = lib.getAttrs (builtins.attrNames (sharedOptions lib)) config.host;
          description = ''
            The host facts both classes declare, as this NixOS host set them.
            modules/core/home.nix forwards them into the primary user's
            home-manager configuration, so the two halves cannot disagree.
          '';
        };

        primaryUser = lib.mkOption {
          type = lib.types.str;
          default = userName;
          description = ''
            Username of the host's primary user. NixOS modules read this to
            locate the matching home-manager.users.<name> entry, so they can
            ask "did the host enable features.docker?" and add the user to the
            docker group accordingly. The flake assumes every NixOS host has
            exactly one HM-managed primary user.
          '';
        };

        installed = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Set true on hosts that target real, post-install hardware. Activates
            the bootloader, the btrfs layout in modules/storage.nix and the
            primary user's home-manager configuration. The installer ISO leaves
            this at the default so the live image keeps using the installation
            media's own root mount and boot loader.
          '';
        };

        luks = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            The btrfs volume sits inside a LUKS2 container on the data
            partition, unlocked by passphrase in the systemd initrd.
            stb-install-nixos formats it that way when this is true, and
            installs onto exactly one disk. Unattended TPM2 unlock is added
            later, without reinstalling, by enrolling a token with
            `systemd-cryptenroll --tpm2-device=auto` once Secure Boot is on.
          '';
        };

        hibernateSwapSize = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 32;
          description = ''
            Size in GiB of a swapfile on its own @swap subvolume, so the
            machine can hibernate. Size it to the RAM: on hibernate, what zram
            holds is written out too. zram keeps the higher priority, so the
            file only takes overflow in normal use. systemd records the resume
            location in an EFI variable and the initrd resumes from it, so no
            resume_offset is needed. Null means no disk swap and no
            hibernation. Part of the disk layout, so decided at install time.
          '';
        };

        secureBoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Replace systemd-boot with lanzaboote (signed bootloader for UEFI
            Secure Boot). DEFAULT FALSE: enabling without enrolling Secure Boot
            keys (sbctl create-keys + sbctl enroll-keys) will brick boot.
            Recommended flow:
              1. Install with secureBoot = false; first-boot to verify.
              2. Run `sudo sbctl create-keys` then `sudo sbctl enroll-keys
                 --microsoft` (or --custom) once firmware is in setup mode.
              3. Flip this flag to true; rebuild; reboot.
          '';
        };

      };
    };
}
