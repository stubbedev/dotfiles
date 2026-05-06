{ config, inputs, ... }:
let
  nixosMods = config.flake.modules.nixos;
  hmMods = config.flake.modules.homeManager;
in
{
  configurations.nixos.stubbe-nixos = {
    system = "x86_64-linux";
    module =
      { config, lib, ... }:
      {
        imports = builtins.attrValues nixosMods ++ [
          inputs.disko.nixosModules.disko
        ];

        networking.hostName = "stubbe-nixos";
        system.stateVersion = "26.05";

        # Stub bootloader and root fs — replace with real values when this
        # configuration targets an actual machine. They keep the toplevel
        # evaluable so `nix build` can verify the closure compiles. After
        # bin/stb-install-nixos formats the disks and the host file is
        # committed with `host.installed = true`, modules/nixos/filesystems.nix
        # takes over and these stubs disappear via the mkIf below.
        boot.loader.systemd-boot.enable = lib.mkIf (!config.host.installed) true;
        boot.loader.efi.canTouchEfiVariables = lib.mkIf (!config.host.installed) true;
        fileSystems."/" = lib.mkIf (!config.host.installed) {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };

        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues hmMods;

          # Gate off privileged activation scripts — the corresponding
          # NixOS modules under modules/nixos/ own those files now.
          host.platform = "nixos";

          features = {
            desktop = true;
            development = true;
            hyprland = true;
            theming = true;
            media = true;
            vpn = true;
            opencode = true;
            srv = true;
            php = false;
            k8s = true;
            claudeCode = true;
            slack = true;
          };
        };
      };
  };
}
