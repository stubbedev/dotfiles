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
      # `boot.blacklistedKernelModules` is the WRONG knob here: it only
      # writes /etc/modprobe.d/nixos.conf (see nixos/modules/system/boot/
      # modprobe.nix:80), which blocks `modprobe` but is ignored by the
      # kernel's own early auto-load path. simpledrm is bound to the
      # EFI simple-framebuffer device by the kernel before any modprobe
      # runs, so the modprobe blacklist never takes effect.
      #
      # `module_blacklist=` on the kernel cmdline is the kernel's
      # built-in blacklist — applies to every load path, including the
      # early auto-bind. Documented in Documentation/admin-guide/kernel-
      # parameters.txt.
      #
      # Trade-off: hosts where neither nvidia, i915, nor amdgpu binds
      # (uncommon ARM / virtio-only / exotic setups) get no early
      # framebuffer at all and lose the splash, but still boot — the
      # firmware splash covers the gap until userspace starts the
      # display manager.
      boot.kernelParams =
        [ "module_blacklist=simpledrm" ]
        ++ lib.optional hasNvidia "nvidia-drm.fbdev=1";
    };
}
