_: {
  flake.modules.nixos.thermald =
    { config, lib, ... }:
    # Intel-only daemon. Skip on AMD/ARM so the unit isn't loaded with
    # nothing to do. Detection via cpuinfo at eval time is impure;
    # checking hardware.cpu.intel.updateMicrocode is a reliable proxy
    # since modules/nixos/hardware.nix only enables it on Intel boxes
    # via mkDefault that mirrors enableRedistributableFirmware.
    lib.mkIf config.hardware.cpu.intel.updateMicrocode {
      # Manages DPTF thermal tables so sustained load isn't stuck at a
      # conservative ceiling. No-op on ThinkPads: thermald sees DYTC
      # (dytc_lapmode) and exits, deferring to the EC + platform_profile.
      services.thermald.enable = true;
    };
}
