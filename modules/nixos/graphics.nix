{ ... }:
{
  flake.modules.nixos.graphics =
    { config, pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      # List every driver the live ISO might encounter. The kernel only
      # binds the one matching the PCI hardware actually present, so on a
      # non-NVIDIA box `nvidia` is harmless. `modesetting` covers Intel/
      # AMD and the generic KMS path; `fbdev` is the last-resort fallback.
      services.xserver.videoDrivers = [
        "nvidia"
        "modesetting"
        "fbdev"
      ];

      hardware.nvidia = {
        modesetting.enable = true;
        # NVIDIA Open Kernel Module (matches the version-detect logic in
        # modules/overlays.nix:9-17 the HM build uses on non-NixOS hosts).
        open = true;
        package = config.boot.kernelPackages.nvidiaPackages.production;
      };
    };
}
