_: {
  flake.modules.nixos.kernel =
    { ... }:
    {
      # Replaces /etc/default/grub.d/intel-pstate-passive.cfg from the
      # non-NixOS activation. NixOS doesn't use that file format; pass the
      # arg directly via boot.kernelParams so the bootloader picks it up.
      boot.kernelParams = [ "intel_pstate=passive" ];
    };
}
