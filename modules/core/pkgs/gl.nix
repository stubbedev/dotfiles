# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# GL/NVIDIA plumbing: nixGL wrappers and the driver paths they inject.
#
# The NVIDIA decision comes from the host options (host.graphicsNvidia,
# host.graphicsNvidiaVersion) and is passed in by the caller -
# modules/core/gfx.nix. It used to probe /proc/driver/nvidia/version, which
# pure eval silently answered false, downgrading every GL wrapper on NVIDIA
# machines to the Intel path.
{ inputs, ... }:
{
  stubbe.pkgsLib.gl =
    {
      final,
      lib,
      ...
    }:
    {
      hasNvidia,
      nvidiaVersion,
    }:
    let
      isIntelX86 = final.stdenv.hostPlatform.system == "x86_64-linux";

      # nixgl's NVIDIA GLX/EGL libraries must match the driver the host OS
      # actually runs, hence the explicit version; the overlay's plain
      # `final.nixgl` builds without one.
      nixgl =
        if hasNvidia && nvidiaVersion != null then
          import "${inputs.nixgl}/default.nix" (
            {
              pkgs = final;
              enable32bits = isIntelX86;
              enableIntelX86Extensions = isIntelX86;
            }
            // {
              inherit nvidiaVersion;
            }
          )
        else
          final.nixgl;

      nixGL = if hasNvidia then (nixgl.nixGLNvidia or nixgl.auto.nixGLNvidia) else nixgl.nixGLIntel;

      nixGLBin = "${nixGL}/bin/${nixGL.name}";

      # `--suffix` lets user-set values win; missing paths are skipped by the
      # loader, but if NONE of a list exists EGL/GBM init fails — hence the
      # RHEL/Arch (lib64), generic (lib) and Debian multiarch layouts below.
      gbmBackendsPath = lib.concatStringsSep ":" [
        "/usr/lib/x86_64-linux-gnu/gbm"
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

      # nixGL's NVIDIA bundle ships no external EGL platform libs, so Nix-built
      # Wayland clients fail with "provided display handle is not supported".
      eglLibs = lib.optionalString hasNvidia (
        lib.concatStringsSep ":" [
          "${final.egl-wayland}/lib"
          "${final.egl-gbm}/lib"
        ]
      );

      eglConfigs = lib.optionalString hasNvidia (
        lib.concatStringsSep ":" [
          "${final.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json"
          "${final.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
        ]
      );
    in
    {
      inherit nixGL nixGLBin;
      nvidia = hasNvidia;

      wrap =
        name: programPath:
        final.runCommand name { nativeBuildInputs = [ final.makeWrapper ]; } ''
          makeWrapper ${nixGLBin} $out/bin/${name} \
            --suffix GBM_BACKENDS_PATH : "${gbmBackendsPath}" \
            --suffix LIBGL_DRIVERS_PATH : "${libglDriversPath}" \
            ${lib.optionalString hasNvidia ''
              --suffix LD_LIBRARY_PATH : "${eglLibs}" \
              --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${eglConfigs}" \
            ''}--add-flag "${programPath}"
        '';
    };
}
