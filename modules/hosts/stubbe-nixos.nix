{ config, inputs, ... }:
let
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
        # Advertised as desktop.local instead: the system hostname is the
        # machine's name on other networks, the mDNS name is its name on the
        # LAN, and only the latter has to line up with stubbe.lib.lanHosts.
        host.mdnsName = "desktop";
        system.stateVersion = "26.05";

        boot.loader = {
          systemd-boot = {
            enable = true;
            # Disable the boot menu's text editor — anyone with physical access
            # could otherwise append `init=/bin/sh` and get a root shell with
            # no password.
            editor = false;
            configurationLimit = 2;
          };
          efi.canTouchEfiVariables = true;
        };

        host.installed = true;
        host.graphicsNvidia = true;

        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues homeModules;
          host.platform = "nixos";
        };
      };
  };
}
