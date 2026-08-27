# stubbe-nixos — the NixOS build of the same machine.
#
# Every `flake.modules.nixos.*` aspect is imported at system level, and every
# `flake.modules.homeManager.*` aspect under the primary user, with
# `host.platform = "nixos"` so each aspect's privileged activation stands down
# in favour of its declarative NixOS half.
{ config, inputs, ... }:
let
  # The inner NixOS module shadows `config`, so bind the two aspect sets here.
  nixosModules = config.flake.modules.nixos;
  homeModules = config.flake.modules.homeManager;
in
{
  configurations.nixos.stubbe-nixos = {
    system = "x86_64-linux";
    module =
      { config, ... }:
      {
        imports = builtins.attrValues nixosModules ++ [ inputs.disko.nixosModules.disko ];

        networking.hostName = "stubbe-nixos";
        system.stateVersion = "26.05";

        # The only target host, and EFI/systemd-boot is what
        # bin/stb-install-nixos provisions.
        boot.loader = {
          systemd-boot = {
            enable = true;
            # Disable the boot menu's text editor — anyone with physical access
            # could otherwise append `init=/bin/sh` and get a root shell with
            # no password.
            editor = false;
            # Match the system-profile prune in modules/nix.nix: current + 1
            # previous in the boot menu, no stale entries.
            configurationLimit = 2;
          };
          efi.canTouchEfiVariables = true;
        };

        # Post-install target, so modules/filesystems.nix supplies the real
        # btrfs layout. The installer ISO leaves this false and uses the
        # installation media's own root mount.
        host.installed = true;

        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues homeModules;
          host.platform = "nixos";
        };
      };
  };
}
