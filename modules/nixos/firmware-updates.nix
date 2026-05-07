_: {
  flake.modules.nixos.firmwareUpdates =
    { ... }:
    {
      # LVFS-backed firmware updates for UEFI/BIOS, SSDs, dock chips,
      # Thunderbolt controllers, etc. Manual flow:
      #   sudo fwupdmgr refresh
      #   sudo fwupdmgr get-updates
      #   sudo fwupdmgr update
      services.fwupd.enable = true;
    };
}
