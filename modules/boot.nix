{ inputs, ... }:
{
  flake.modules.nixos.boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lys.nixosModules.lys-splash ];

      boot = {
        loader = lib.mkIf config.host.installed {
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

        lys-splash = {
          enable = true;
          package = pkgs.lys-splash;
        };

        kernelParams = [
          "quiet"
          "rd.systemd.show_status=auto"
          "rd.udev.log_level=3"
        ];
        consoleLogLevel = lib.mkDefault 3;
      };
    };

  flake.modules.nixos.secureBoot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      config = lib.mkIf config.host.secureBoot {
        boot.loader.systemd-boot.enable = lib.mkForce false;

        boot.lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
        };

        environment.systemPackages = [ pkgs.sbctl ];
      };
    };
}
