{ inputs, ... }:
{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.lys-splash.nixosModules.default ];

      boot = {
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

  flake.modules.homeManager.boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stubbe.setup.lysSplash = lib.mkIf config.features.theming {
        privileged = true;
        title = "Installing lys-splash (the boot splash, in place of Plymouth)";
        body = ''
          Remove Plymouth and its old theme, install lys-splash under /usr, enable
          its units, ensure `quiet splash` is on the kernel cmdline, and rebuild
          every kernel's initrd.

          The cmdline edit is a /etc/default/grub.d drop-in, so deleting it and
          running update-grub recovers it, and update-initramfs replaces an initrd
          atomically. To boot without the splash once, add plymouth.enable=0 to
          the kernel cmdline.
        '';
        script = ''
          if ! command -v apt-get >/dev/null 2>&1; then
            echo "lys-splash installs through initramfs-tools here; this host has no apt-get." >&2
            exit 1
          fi

          sudo apt-get remove -y plymouth
          sudo rm -rf /usr/share/plymouth/themes/catppuccin-mocha
          sudo rm -f /etc/default/grub.d/50-plymouth-splash.cfg

          sudo cp -a --no-preserve=ownership ${pkgs.lys-splash.compat}/. /usr/
          sudo systemctl enable \
            lys-splash-start.service lys-splash-quit.service \
            lys-splash-quit-wait.service lys-splash-read-write.service \
            lys-splash-ask-password.path lys-splash-reboot.service \
            lys-splash-poweroff.service lys-splash-halt.service lys-splash-kexec.service

          ${pkgs.stubbe.setup.text {
            name = "50-lys-splash.cfg";
            target = "/etc/default/grub.d/50-lys-splash.cfg";
            text = ''
              GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} quiet splash"
            '';
          }}
          sudo update-grub
          sudo update-initramfs -u -k all
        '';
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
