_: {
  flake.modules.homeManager.platform =
    { lib, ... }:
    {
      options.host = {
        platform = lib.mkOption {
          type = lib.types.enum [
            "linux"
            "nixos"
          ];
          default = "linux";
          description = ''
            Host platform. "linux" means home-manager on a non-NixOS distro
            (Fedora, Ubuntu, …), where the privileged half of each aspect —
            /etc/pam.d, udev rules, polkit, apparmor, host packages — is
            managed by `stubbe.setup.<name>.privileged` activations. "nixos"
            means the matching NixOS module owns those files instead, and every
            privileged activation is gated off.
          '';
        };

        graphicsNvidia = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            The machine's display GPU is NVIDIA. Drives the standalone
            home-manager GL wiring: modules/core/pkgs/gl.nix picks the NVIDIA
            nixGL variant and its EGL platform libs when true, the Intel/AMD
            one when false. NixOS hosts carry the same option on the NixOS
            side, where modules/graphics.nix selects the kernel driver stack
            from it. Replaces the /proc probe, which pure eval silently
            answered false.
          '';
        };

        graphicsNvidiaVersion = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Version of the NVIDIA driver the host OS runs - on NixOS whatever
            hardware.nvidia.package resolves to (e.g. "595.104.02"), elsewhere
            the distro package's version. nixGL's NVIDIA GLX/EGL libraries
            must match it. Read only when host.graphicsNvidia is true.
          '';
        };
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

        graphicsNvidia = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            The host's display GPU is NVIDIA. Replaces the /proc probe that
            forced --impure on every rebuild: modules/graphics.nix selects
            the nvidia driver stack when true and the intel/amdgpu defaults
            when false. Set it in the host's declaration
            (modules/hosts/<name>.nix).
          '';
        };
      };
    };
}
