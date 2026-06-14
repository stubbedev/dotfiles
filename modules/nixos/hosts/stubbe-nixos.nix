{ config, inputs, ... }:
let
  nixosMods = config.flake.modules.nixos;
  hmMods = config.flake.modules.homeManager;
  hmLinux = config.linuxOnlyHomeModules;
in
{
  configurations.nixos.stubbe-nixos = {
    system = "x86_64-linux";
    module =
      { config, ... }:
      {
        imports = builtins.attrValues nixosMods ++ [
          inputs.disko.nixosModules.disko
        ];

        networking.hostName = "stubbe-nixos";
        system.stateVersion = "26.05";

        # Real bootloader: this is the only target host, EFI/systemd-boot
        # is what bin/stb-install-nixos provisions.
        boot.loader = {
          systemd-boot = {
            enable = true;
            # Disable the boot menu's text editor — anyone with physical
            # access could otherwise append `init=/bin/sh` and get a root
            # shell without a password.
            editor = false;
            # Match the system-profile prune in modules/nixos/nix-gc.nix:
            # current + 1 previous in the boot menu, no stale entries.
            configurationLimit = 2;
          };
          efi.canTouchEfiVariables = true;
        };

        # Mark this host as the post-install target so
        # modules/nixos/filesystems.nix supplies the real btrfs layout.
        # The installer ISO leaves host.installed at its default (false)
        # and uses the cd-dvd installation media's own root mount.
        host.installed = true;

        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues hmMods ++ builtins.attrValues hmLinux;

          # Gate off privileged activation scripts — the corresponding
          # NixOS modules under modules/nixos/ own those files now.
          host.platform = "nixos";
        };
      };
  };
}
