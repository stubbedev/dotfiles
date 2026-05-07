_: {
  flake.modules.nixos.thermald =
    { config, lib, ... }:
    # Intel-only daemon. Skip on AMD/ARM so the unit isn't loaded with
    # nothing to do. Detection via cpuinfo at eval time is impure;
    # checking hardware.cpu.intel.updateMicrocode is a reliable proxy
    # since modules/nixos/hardware.nix only enables it on Intel boxes
    # via mkDefault that mirrors enableRedistributableFirmware.
    lib.mkIf config.hardware.cpu.intel.updateMicrocode {
      # Adjusts the Intel P-state governor + thermal trip points so the
      # CPU doesn't run at a fixed conservative ceiling. Fixes the
      # all-cores-at-400MHz problem some laptops show under heavy load.
      services.thermald.enable = true;
    };
}
