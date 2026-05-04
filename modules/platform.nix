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
}
