# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# GL plumbing for standalone home-manager hosts: wraps GL programs so they
# find working drivers on a foreign distro.
#
# The NVIDIA-vs-else decision comes from the host option host.graphicsNvidia
# (modules/core/platform.nix), passed in by modules/core/gfx.nix. It used to
# be a /proc probe, which pure eval silently answered false and downgraded
# NVIDIA machines to the Intel path.
#
# No driver version appears anywhere by design: on NVIDIA hosts the wrapper
# points glvnd at the host's own vendor libraries under /usr - the same files
# the OS driver package installed - so they match the running kernel module
# by construction and follow every driver update on their own.
_: {
  stubbe.pkgsLib.gl =
    {
      final,
      lib,
      ...
    }:
    { hasNvidia }:
    let
      # `--suffix` lets user-set values win; missing paths are skipped by the
      # loader, but if NONE of a list exists EGL/GBM init fails — hence the
      # Debian multiarch, RHEL/Arch (lib64) and generic (lib) layouts below.
      # Distro-verified 2026-10-03 against package file lists:
      #   Arch   nvidia-utils: /usr/lib{,/gbm}
      #   Ubuntu libnvidia-gl-flavour.install: multiarch root + multiarch/gbm
      #   Debian trixie Contents: libs + nvidia-drm_gbm.so under
      #          multiarch/nvidia/current (alternatives flavour layout)
      #   Fedora xorg-x11-drv-nvidia-libs: /usr/lib64{,/gbm}
      #   openSUSE: /usr/lib64/nvidia
      gbmBackendsPath = lib.concatStringsSep ":" [
        "/usr/lib/x86_64-linux-gnu/gbm"
        "/usr/lib/x86_64-linux-gnu/nvidia/current"
        "/usr/lib64/gbm"
        "/usr/lib/gbm"
        "/run/opengl-driver/lib/gbm"
        "/run/opengl-driver-32/lib/gbm"
      ];
      libglDriversPath = lib.concatStringsSep ":" [
        "/usr/lib/x86_64-linux-gnu/dri"
        "/usr/lib64/dri"
        "/usr/lib/dri"
        "/run/opengl-driver/lib/dri"
        "/run/opengl-driver-32/lib/dri"
      ];

      # NVIDIA vendor userspace (libEGL_nvidia, libGLX_nvidia, libnvidia-ml,
      # …) lives wherever the distro driver package put it: multiarch root
      # (Ubuntu), multiarch/nvidia/current (Debian), /usr/lib64/nvidia
      # (openSUSE), /usr/lib64 (Fedora/RHEL) or /usr/lib (Arch) — matched to
      # the kernel module because it IS the driver package's own files.
      hostDriverLibs = lib.concatStringsSep ":" [
        "/usr/lib/x86_64-linux-gnu"
        "/usr/lib/x86_64-linux-gnu/nvidia/current"
        "/usr/lib64/nvidia"
        "/usr/lib64"
        "/usr/lib"
      ];

      # NVIDIA's external EGL platform descriptors: the host's first
      # (driver-matched; Ubuntu and Fedora ship 15_nvidia_gbm/20_nvidia_xlib
      # here, egl-wayland ships 10_nvidia_wayland on every distro), nixpkgs'
      # copies as fallback.
      eglExternalPlatforms = lib.concatStringsSep ":" [
        "/usr/share/egl/egl_external_platform.d"
        "${final.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json"
        "${final.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
      ];
    in
    {
      nvidia = hasNvidia;

      wrap =
        name: programPath:
        final.runCommand name { nativeBuildInputs = [ final.makeWrapper ]; } (
          if hasNvidia then
            ''
              # glvnd (linked by the program itself) dispatches to the NVIDIA
              # vendor ICD from the host OS. Nothing bundled, nothing to keep
              # in version lockstep.
              makeWrapper ${programPath} $out/bin/${name} \
                --set __GLX_VENDOR_LIBRARY_NAME nvidia \
                --suffix __EGL_VENDOR_LIBRARY_FILENAMES : /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
                --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${eglExternalPlatforms}" \
                --suffix LD_LIBRARY_PATH : "${hostDriverLibs}" \
                --suffix GBM_BACKENDS_PATH : "${gbmBackendsPath}" \
                --suffix LIBGL_DRIVERS_PATH : "${libglDriversPath}"
            ''
          else
            let
              nixGL = final.nixgl.nixGLIntel;
            in
            ''
              makeWrapper ${nixGL}/bin/${nixGL.name} $out/bin/${name} \
                --suffix GBM_BACKENDS_PATH : "${gbmBackendsPath}" \
                --suffix LIBGL_DRIVERS_PATH : "${libglDriversPath}" \
                --add-flag "${programPath}"
            ''
        );
    };
}
