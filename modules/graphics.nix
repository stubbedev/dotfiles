_: {
  flake.modules.nixos.graphics =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Set per host (host.graphicsNvidia) instead of probing /proc, which
      # forced --impure on every rebuild.
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
              "amdgpu"
            ];

        # Plymouth attaches to simpledrm's framebuffer, which is freed when the real
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

      # Without this the machine hangs at the end of poweroff: the proprietary
      # driver's .shutdown() deadlocks in device_shutdown(), and this host has
      # no iGPU so nvidia is always still loaded when that runs.
      systemd.services.nvidia-unload-on-shutdown = lib.mkIf hasNvidia {
        description = "Unload NVIDIA modules before power-off (shutdown-hang workaround)";
        wantedBy = [ "multi-user.target" ];
        # Stop order is the reverse of start order, so this runs after the
        # compositor has released the GPU.
        before = [
          "greetd.service"
          "display-manager.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          TimeoutStopSec = 20;
          ExecStop = pkgs.stubbe.shellScript "nvidia-unload-on-shutdown" ''
            for vt in /sys/class/vtconsole/vtcon*; do
              if grep -qi 'frame buffer' "$vt/name" 2>/dev/null; then
                echo 0 > "$vt/bind" 2>/dev/null || true
              fi
            done
            for module in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
              ${pkgs.kmod}/bin/modprobe -r "$module" 2>/dev/null || true
            done
          '';
        };
      };

    };
}
