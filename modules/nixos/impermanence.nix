{ inputs, ... }:
{
  flake.modules.nixos.impermanence =
    {
      config,
      lib,
      ...
    }:
    lib.mkIf (config.host.installed && config.host.impermanent) {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      # Roll back the @ subvol to the @-blank snapshot taken by
      # bin/stb-install-nixos before nixos-install populated it. Runs
      # in the initrd before any service touches the filesystem, so the
      # current generation's activation script repopulates /etc + /var
      # from scratch on every boot — only paths declared in
      # `environment.persistence."/persist"` survive.
      boot.initrd.systemd.services.rollback-root = {
        description = "Rollback / to @-blank";
        wantedBy = [ "initrd.target" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /btrfs_tmp
          mount -t btrfs -o subvol=/ /dev/disk/by-label/stubbe /btrfs_tmp
          if [ -e /btrfs_tmp/@ ]; then
            btrfs subvolume delete /btrfs_tmp/@
          fi
          btrfs subvolume snapshot /btrfs_tmp/@-blank /btrfs_tmp/@
          umount /btrfs_tmp
        '';
      };

      # Declarative persistence. Anything outside this list is wiped on
      # every boot. NixOS activation rebuilds /etc, /run, and most of
      # /var from the system closure, so only state that changes at
      # runtime needs to land here.
      environment.persistence."/persist" = {
        hideMounts = true;
        directories = [
          "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
          "/var/lib/systemd/timers"
          "/var/lib/NetworkManager"
          "/var/lib/sops-nix"
          "/var/lib/sbctl"
          "/var/lib/upower"
          "/etc/NetworkManager/system-connections"
          "/etc/nixos"
        ];
        files = [
          "/etc/machine-id"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_rsa_key.pub"
        ];
      };

      # /home is its own subvol (persistent) but anything bind-mounted
      # from there to a system path needs explicit listing too. None
      # currently — HM owns ~/.config and ~/.local.

      # sops-nix expects /etc/ssh/ssh_host_ed25519_key to exist BEFORE
      # the rollback wipe takes effect, since it's listed in
      # modules/nixos/sops.nix as the age key path. Persisting it via
      # impermanence covers that.
      programs.fuse.userAllowOther = true;
    };
}
