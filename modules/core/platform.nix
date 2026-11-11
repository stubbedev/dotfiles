{ config, ... }:
let
  inherit (config.stubbe.lib) userName lanHosts;

  sharedOptions = lib: host: {
    flakeAttr = lib.mkOption {
      type = lib.types.str;
      description = ''
        The attribute this machine's configuration is defined under.
        modules/core/configurations.nix sets it from the attribute name.
      '';
    };

    mdnsName = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames lanHosts));
      default = if lanHosts ? ${host.flakeAttr} then host.flakeAttr else null;
      defaultText = lib.literalMD "`host.flakeAttr` when it is a key of `stubbe.lib.lanHosts`, else null";
      description = ''
        The name this host advertises over mDNS: it is reachable as
        `<mdnsName>.local`, which is the key it carries in
        `stubbe.lib.lanHosts` (modules/core/lib/lan-hosts.nix). On NixOS it
        feeds `services.avahi.settings.server."host-name"`. Null leaves
        avahi on the system hostname, which then also gains avahi's
        collision counter suffix (`-2`, `-3`, …) whenever an interface
        publishes it twice.
      '';
    };

    graphicsNvidia = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The machine's display GPU is NVIDIA. The one GPU decision a host
        makes; versions, kernel modules and userspace follow from nixpkgs
        and the distro driver package on their own. On NixOS,
        modules/graphics.nix selects the nvidia driver stack from it. Under
        standalone home-manager, modules/core/pkgs/gl.nix wraps programs for
        glvnd NVIDIA vendor dispatch against the host's own driver libraries
        when true, and uses nixGLIntel when false.
      '';
    };

    battery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "The machine runs on a battery, so the desktop shell shows its charge.";
    };
  };
in
{
  flake.modules.homeManager.platform =
    { config, lib, ... }:
    {
      options.host = sharedOptions lib config.host // {
        platform = lib.mkOption {
          type = lib.types.enum [
            "linux"
            "nixos"
            "android"
          ];
          default = "linux";
          description = ''
            Host platform. "linux" means home-manager on a non-NixOS distro
            (Fedora, Ubuntu, …), where the privileged half of each aspect —
            /etc/pam.d, udev rules, polkit, apparmor, host packages — is
            managed by `stubbe.setup.<name>.privileged` activations. "nixos"
            means the matching NixOS module owns those files instead, and every
            privileged activation is gated off. "android" means nix-on-droid
            inside Termux: a proot'd glibc environment with no init, no
            D-Bus, no /etc and no /usr, where neither a privileged activation
            nor a systemd unit can run at all.
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
      options.host = sharedOptions lib config.host // {
        sharedFacts = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          readOnly = true;
          default = lib.getAttrs (builtins.attrNames (sharedOptions lib config.host)) config.host;
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

        impermanent = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Roll the root subvolume back to its empty @-blank snapshot on every
            boot, keeping only what modules/impermanence.nix persists under
            /persist. /var then lives on the root subvolume instead of its own
            @var, so it is wiped too. The layout differs from a persistent
            host's, so this is decided at install time: stb-install-nixos
            reads it and lays the disk out to match.
          '';
        };
      };
    };
}
