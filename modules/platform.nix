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
      options.host.primaryUser = lib.mkOption {
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

      options.host.installed = lib.mkOption {
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
    };
}
