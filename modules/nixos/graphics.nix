{ ... }:
let
  # Pure-eval safety check. `/proc` is always present on Linux, so a
  # `pathExists` miss here means the flake was evaluated without
  # `--impure`. In that case `hasNvidia` below would silently return
  # false and a rebuild would drop nvidia from a working system —
  # throw a loud, actionable error instead.
  isImpure = builtins.pathExists (/. + "/proc");

  # Build-time GPU detection. Reads /proc/driver/nvidia/version, which
  # only exists once nvidia.ko has loaded — so the live installer ISO
  # force-loads `nvidia` at boot (modules/installer/iso.nix) to make
  # detection work for `stb-install-nixos --impure`.
  #
  # Sysfs would be the ideal source (PCI vendor 0x10de is exposed for
  # every device whether or not a driver is bound), but Nix's readFile
  # fails on sysfs files: the kernel reports size = PAGE_SIZE (4096)
  # while the actual content is a handful of bytes, and the evaluator
  # treats the size mismatch as `unexpected end-of-file`.
  hasNvidia =
    if isImpure then
      builtins.pathExists (/. + "/proc/driver/nvidia/version")
    else
      throw ''
        graphics.nix requires --impure to detect GPU hardware.
        Rebuild with:
          sudo nixos-rebuild switch --flake /etc/nixos/dotfiles#stubbe-nixos --impure
        Without --impure, nvidia detection silently fails and your
        working nvidia setup would be rebuilt away.
      '';
in
{
  flake.modules.nixos.graphics =
    { config, lib, pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      # Always ship the NVIDIA open kernel module in the closure so the
      # driver is available regardless of whether this host currently
      # has an NVIDIA card. On non-NVIDIA hosts the ~150MB sits in
      # /nix/store unused; the upside is a GPU swap becomes self-
      # healing — see `boot.kernelModules` below.
      boot.extraModulePackages = [
        config.boot.kernelPackages.nvidiaPackages.production.open
      ];

      # Force-load nvidia.ko on every boot. On NVIDIA hardware this
      # populates /proc/driver/nvidia/version, which `hasNvidia` above
      # reads on the *next* rebuild to enable the full nvidia stack.
      # On non-NVIDIA hardware the insert fails with -ENODEV;
      # systemd-modules-load tolerates that (warning, boot continues).
      #
      # Practical effect: GPU swap → reboot → `nixos-rebuild switch
      # --impure`. No manual modprobe; the rebuild picks up the new
      # state because /proc reflects whatever loaded this boot.
      boot.kernelModules = [ "nvidia" ];

      # `modesetting` covers Intel/AMD/nouveau KMS; `fbdev` is the
      # last-resort fallback. `nvidia` is only listed when detection
      # confirms the hardware is actually present, so xserver doesn't
      # waste a probe trying nvidia on non-NVIDIA boxes.
      services.xserver.videoDrivers =
        lib.optionals hasNvidia [ "nvidia" ] ++ [ "modesetting" "fbdev" ];

      hardware.nvidia = lib.mkIf hasNvidia {
        modesetting.enable = true;
        # NVIDIA Open Kernel Module — matches modules/overlays.nix:6-17
        # which the HM build uses on non-NixOS hosts, and matches the
        # `.open` variant pulled into the closure unconditionally above.
        open = true;
        package = config.boot.kernelPackages.nvidiaPackages.production;
      };

      # Workaround for the machine hanging at the very end of `poweroff`
      # / `reboot`: fans, CPU and the GPU's RGB strip stay powered and
      # the screen goes black, but power is never actually cut.
      #
      # Before cutting power, the kernel runs every driver's
      # `.shutdown()` callback inside `device_shutdown()`. The
      # proprietary NVIDIA driver's shutdown callback can deadlock
      # there. This host's CPU is an "F" SKU with no iGPU, so the
      # NVIDIA modules drive the only display and stay pinned until
      # very late shutdown — the driver is always present when
      # device_shutdown() runs.
      #
      # Fix: unbind the framebuffer console (fbcon keeps nvidia_drm
      # pinned even after the compositor exits) and unload the NVIDIA
      # stack in an ExecStop hook. `before = greetd.service` makes
      # systemd stop this unit *after* the display manager on shutdown
      # (stop order is the reverse of start order), so the compositor
      # has already released the GPU. Every step is `|| true` — a
      # failed unload must never make shutdown worse than it is.
      systemd.services.nvidia-unload-on-shutdown = lib.mkIf hasNvidia {
        description = "Unload NVIDIA modules before power-off (shutdown-hang workaround)";
        wantedBy = [ "multi-user.target" ];
        before = [ "greetd.service" "display-manager.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          TimeoutStopSec = 20;
          ExecStop = pkgs.writeShellScript "nvidia-unload-on-shutdown" ''
            # Detach fbcon from the NVIDIA framebuffer so nothing pins
            # nvidia_drm once the compositor is gone.
            for vt in /sys/class/vtconsole/vtcon*; do
              if grep -qi 'frame buffer' "$vt/name" 2>/dev/null; then
                echo 0 > "$vt/bind" 2>/dev/null || true
              fi
            done
            # Unload in dependency order; never block shutdown on it.
            for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
              ${pkgs.kmod}/bin/modprobe -r "$m" 2>/dev/null || true
            done
          '';
        };
      };

      # Force the matching GPU driver into stage 1 so Plymouth has a
      # real DRM device to attach to, instead of the EFI framebuffer
      # surrogate that simpledrm exposes briefly before being torn down
      # by the real driver — that handoff was the cause of the "splash
      # silently paints into a freed surface, user sees TTY underneath"
      # symptom.
      #
      # nvidia: only the nvidia stack (nouveau would conflict).
      # non-nvidia: include i915 + amdgpu unconditionally. The kernel
      #             only binds the module whose PCI ID actually matches
      #             present hardware, so the unmatched one is inert.
      #             nouveau is intentionally omitted — it doesn't go
      #             through simpledrm-style takeover and would just
      #             bloat stage 1.
      boot.initrd.kernelModules =
        if hasNvidia then
          [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]
        else
          [ "i915" "amdgpu" ];

      # simpledrm registers /dev/dri/card0 from the EFI framebuffer at
      # kernel start, then is torn down when the real GPU driver loads.
      # If Plymouth attached to simpledrm in that window (which it
      # always did, because plymouth-start runs before initrd
      # kernel-modules-load completes), its drawing surface is freed
      # underneath it — the splash continues "running" per the journal
      # but is no longer visible.
      #
      # On NixOS the kernel ships with CONFIG_DRM_SIMPLEDRM=y — simpledrm
      # is *built into vmlinuz*, not a loadable module. Verified by
      # `zgrep DRM_SIMPLEDRM /proc/config.gz` and by `lsmod | grep
      # simpledrm` returning empty while the journal still shows
      # `[drm] Initialized simpledrm 1.0.0`. Two consequences:
      #
      #   1. `boot.blacklistedKernelModules` (writes
      #      /etc/modprobe.d/nixos.conf) is a no-op — built-in code
      #      doesn't go through modprobe.
      #   2. `module_blacklist=simpledrm` on the cmdline is also a
      #      no-op — that param only matches loadable modules.
      #
      # `initcall_blacklist=` is the kernel's own knob that does match
      # built-in initcalls. The exact function name was confirmed from
      # this kernel's System.map:
      #   ffffffff837f2e80 t simpledrm_platform_driver_init
      # (`module_platform_driver(simpledrm_platform_driver)` macro-
      # expands into a `_init` initcall at level 6.)
      #
      # Trade-off: hosts where neither nvidia, i915, nor amdgpu binds
      # (uncommon ARM / virtio-only / exotic setups) get no early
      # framebuffer at all and lose the splash, but still boot — the
      # firmware splash covers the gap until userspace starts the
      # display manager.
      boot.kernelParams =
        [ "initcall_blacklist=simpledrm_platform_driver_init" ]
        ++ lib.optional hasNvidia "nvidia-drm.fbdev=1";
    };
}
