{ config, ... }:
let
  inherit (config.stubbe.lib) userName;

  sharedOptions = lib: {
    mdnsName = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrNames config.stubbe.lib.lanHosts));
      default = null;
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
  };
in
{
  flake.modules.homeManager.platform =
    { lib, ... }:
    {
      options.host = sharedOptions lib // {
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

        battery = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "The machine runs on a battery, so the desktop shell shows its charge.";
        };

        flakeAttr = lib.mkOption {
          type = lib.types.str;
          description = ''
            The attribute this machine's configuration is defined under.
            modules/core/configurations.nix sets it from the attribute name.
          '';
        };
      };
    };

  flake.modules.nixos.platform =
    { lib, ... }:
    {
      options.host = sharedOptions lib // {
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
            Set true on hosts that target real, post-install hardware (e.g.
            `stubbe-nixos`). Activates the real btrfs layout in
            modules/storage.nix and inhibits any stub fileSystems that
            exist purely to keep a fresh checkout `nix build`-evaluable. The
            installer ISO leaves this at the default so the live image keeps
            using the installation media's own root mount.
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
            Wipe the root subvolume on every boot, persisting only declared
            paths under /persist. DEFAULT FALSE: enabling on a system that
            hasn't been laid out for impermanence will lose state.
            Recommended flow:
              1. Install with impermanent = false; the install script creates
                 an @-blank snapshot of the empty @ subvol so the flag is safe
                 to flip later.
              2. Audit the persistence list in modules/impermanence.nix; add
                 anything host-specific.
              3. Flip this flag to true; rebuild; reboot.
          '';
        };
      };
    };
}
