{ config, ... }:
let
  nixosMods = config.flake.modules.nixos;
  hmMods = config.flake.modules.homeManager;
in
{
  configurations.nixos.stubbe-nixos = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues nixosMods;

      networking.hostName = "stubbe-nixos";
      system.stateVersion = "26.05";

      # Stub bootloader and root fs — replace with real values when this
      # configuration targets an actual machine. They keep the toplevel
      # evaluable so `nix build` can verify the closure compiles.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      users.users.stubbe = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "video"
          "audio"
          "networkmanager"
        ];
      };

      services.openssh.enable = true;
      networking.networkmanager.enable = true;

      home-manager.users.stubbe = {
        imports = builtins.attrValues hmMods;

        # Gate off privileged activation scripts — corresponding NixOS
        # modules under modules/nixos/ own those files now.
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
