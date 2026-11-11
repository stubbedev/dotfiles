{ inputs, ... }:
{
  flake.modules.nixos.impermanence =
    {
      config,
      lib,
      options,
      utils,
      ...
    }:
    let
      inherit (config.stubbe) storage;
      persist = "/persist";
      btrfsDeviceUnit = "${utils.escapeSystemdPath storage.btrfsDevice}.device";
      features = config.stubbe.userFeatures;
    in
    {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      config = lib.mkIf config.host.impermanent {
        assertions = [
          {
            assertion = config.host.installed;
            message = "host.impermanent rolls back the installed root subvolume; set host.installed too.";
          }
        ];

        fileSystems.${persist}.neededForBoot = true;

        users = {
          mutableUsers = false;
          users.${config.host.primaryUser}.hashedPasswordFile =
            "${persist}/passwords/${config.host.primaryUser}";
        };

        boot.initrd.systemd.services.rollback-root = {
          description = "Roll / back to the empty ${storage.blankSnapshot} snapshot";
          wantedBy = [ "initrd.target" ];
          requires = [ btrfsDeviceUnit ];
          after = [ btrfsDeviceUnit ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            top=/run/rollback-root
            mkdir -p "$top"
            mount -t btrfs -o subvol=/ ${storage.btrfsDevice} "$top"

            delete_subvolume() {
              local child
              while IFS= read -r child; do
                delete_subvolume "$top/$child"
              done < <(btrfs subvolume list -o "$1" | cut -d' ' -f9-)
              btrfs subvolume delete "$1"
            }

            if [ -e "$top/${storage.rootSubvolume}" ]; then
              delete_subvolume "$top/${storage.rootSubvolume}"
            fi
            btrfs subvolume snapshot "$top/${storage.blankSnapshot}" "$top/${storage.rootSubvolume}"
            umount "$top"
          '';
        };

        services.openssh.hostKeys = map (
          key: key // { path = persist + key.path; }
        ) options.services.openssh.hostKeys.default;

        environment.persistence.${persist} = {
          hideMounts = true;
          directories = [
            "/etc/nixos"
            "/etc/NetworkManager/system-connections"
            "/var/log"
            "/var/lib/nixos"
            "/var/lib/systemd"
            "/var/lib/NetworkManager"
            "/var/lib/bluetooth"
            "/var/lib/upower"
            "/var/lib/power-profiles-daemon"
            "/var/lib/adaptive-power-manager"
            "/var/lib/fwupd"
            {
              directory = "/var/lib/private";
              mode = "0700";
            }
          ]
          ++ lib.optional config.programs.lys-login.greeter.enable "/var/lib/lys-greeter"
          ++ lib.optional config.host.secureBoot config.boot.lanzaboote.pkiBundle
          ++ lib.optional config.services.hardware.bolt.enable "/var/lib/boltd"
          ++ lib.optional config.services.fprintd.enable "/var/lib/fprint"
          ++ lib.optionals features.docker [
            "/var/lib/docker"
            "/var/lib/containerd"
          ];
          files = [ "/etc/machine-id" ];
        };
      };
    };
}
