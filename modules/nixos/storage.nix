_: {
  flake.modules.nixos.storage =
    { ... }:
    {
      # SMART monitoring: polls every disk on a timer, logs failing
      # attributes to the journal. No email destination configured —
      # `journalctl -u smartd` surfaces alerts. autodetect picks up
      # every /dev/sd*, /dev/nvme* without per-host config.
      services.smartd = {
        enable = true;
        autodetect = true;
        notifications.x11.enable = true;
      };

      # Auto-mount removable media (USB sticks, SD cards, MTP). waybar's
      # disk widget + file managers (vifm, nautilus) read its dbus API.
      services.udisks2.enable = true;
    };
}
