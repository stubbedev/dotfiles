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
        default = builtins.pathExists "/etc/stubbe-installed";
        defaultText = lib.literalExpression ''builtins.pathExists "/etc/stubbe-installed"'';
        description = ''
          False on a freshly-checked-out host (stub bootloader + stub root
          fileSystem keep `nix build` evaluable). True once /etc/stubbe-installed
          exists — stb-install-nixos touches the marker on both the live ISO
          (so install-time eval picks the real btrfs layout from
          modules/nixos/filesystems.nix) and on /mnt/etc/ (so post-install
          rebuilds keep the same shape). Reading the marker requires --impure,
          which the flake already runs under.
        '';
      };
    };
}
