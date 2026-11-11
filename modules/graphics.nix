_: {
  flake.modules.nixos.graphics =
    {
      config,
      lib,
      ...
    }:
    let
      hasNvidia = config.host.graphicsNvidia;
    in
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      boot = {
        extraModulePackages = [
          config.boot.kernelPackages.nvidiaPackages.production.open
        ];

        # Loads on non-NVIDIA hosts too, where it fails -ENODEV without the
        # hardware; systemd-modules-load tolerates that.
        kernelModules = [ "nvidia" ];

        # nouveau is omitted deliberately; the kernel only binds whichever of
        # i915/amdgpu matches real hardware.
        initrd.kernelModules =
          if hasNvidia then
            [
              "nvidia"
              "nvidia_modeset"
              "nvidia_uvm"
              "nvidia_drm"
            ]
          else
            [
              "i915"
              "xe"
              "amdgpu"
            ];

        # The boot splash attaches to simpledrm's framebuffer, which is freed when the real
        # GPU driver loads, and then paints into nothing. simpledrm is CONFIG=y here,
        # so blacklistedKernelModules and module_blacklist= are both no-ops.
        kernelParams = [
          "initcall_blacklist=simpledrm_platform_driver_init"
        ]
        ++ lib.optional hasNvidia "nvidia-drm.fbdev=1";
      };

      services.xserver.videoDrivers = lib.optionals hasNvidia [ "nvidia" ] ++ [
        "modesetting"
        "fbdev"
      ];

      hardware.nvidia = lib.mkIf hasNvidia {
        modesetting.enable = true;
        open = true;
        package = config.boot.kernelPackages.nvidiaPackages.production;
      };

    };
}
