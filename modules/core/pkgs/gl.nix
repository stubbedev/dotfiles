# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# GL/NVIDIA plumbing: nixGL wrappers and the driver paths they inject.
_: {
  stubbe.pkgsLib = {
    hasNvidia = _: builtins.pathExists (/. + "/proc/driver/nvidia/version");

    # nixGLNvidia only exists when the overlay's eval-time detection worked;
    # builtins.readFile returns "" on kernels reporting /proc as zero-sized.
    # The `auto` set copies the file in a runCommand and always detects.
    nixGL =
      {
        final,
        stubbe,
        ...
      }:
      if stubbe.hasNvidia then
        (final.nixgl.nixGLNvidia or final.nixgl.auto.nixGLNvidia)
      else
        final.nixgl.nixGLIntel;

    # `--suffix` lets user-set values win; missing paths are skipped by the
    # loader, but if NONE of a list exists EGL/GBM init fails — hence the
    # RHEL/Arch (lib64), generic (lib) and Debian multiarch layouts below.

    nixGLBin =
      { stubbe, ... }:
      "${stubbe.nixGL}/bin/${stubbe.nixGL.name}";

    # `--suffix` lets user-set values win; missing paths are skipped by the
    # loader, but if NONE of a list exists EGL/GBM init fails — hence the
    # RHEL/Arch (lib64), generic (lib) and Debian multiarch layouts below.
    mkGLWrapper =
      {
        final,
        lib,
        stubbe,
        ...
      }:
      name: programPath:
      final.runCommand name { nativeBuildInputs = [ final.makeWrapper ]; } ''
        makeWrapper ${stubbe.nixGLBin} $out/bin/${name} \
          --suffix GBM_BACKENDS_PATH : "${stubbe.driverEnv.GBM_BACKENDS_PATH}" \
          --suffix LIBGL_DRIVERS_PATH : "${stubbe.driverEnv.LIBGL_DRIVERS_PATH}" \
          ${lib.optionalString stubbe.hasNvidia ''
            --suffix LD_LIBRARY_PATH : "${stubbe.nvidiaEglLibs}" \
            --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${stubbe.nvidiaEglConfigs}" \
          ''}--add-flag "${programPath}"
      '';

    driverEnv =
      { lib, ... }:
      {
        GBM_BACKENDS_PATH = lib.concatStringsSep ":" [
          "/usr/lib/x86_64-linux-gnu/gbm"
          "/usr/lib64/gbm"
          "/usr/lib/gbm"
          "/run/opengl-driver/lib/gbm"
          "/run/opengl-driver-32/lib/gbm"
        ];
        LIBGL_DRIVERS_PATH = lib.concatStringsSep ":" [
          "/usr/lib/x86_64-linux-gnu/dri"
          "/usr/lib64/dri"
          "/usr/lib/dri"
          "/run/opengl-driver/lib/dri"
          "/run/opengl-driver-32/lib/dri"
        ];
      };

    # nixGL's NVIDIA bundle ships no external EGL platform libs, so Nix-built
    # Wayland clients fail with "provided display handle is not supported".
    nvidiaEglLibs =
      {
        final,
        lib,
        stubbe,
        ...
      }:
      lib.optionalString stubbe.hasNvidia (
        lib.concatStringsSep ":" [
          "${final.egl-wayland}/lib"
          "${final.egl-gbm}/lib"
        ]
      );

    nvidiaEglConfigs =
      {
        final,
        lib,
        stubbe,
        ...
      }:
      lib.optionalString stubbe.hasNvidia (
        lib.concatStringsSep ":" [
          "${final.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json"
          "${final.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
        ]
      );
  };
}
