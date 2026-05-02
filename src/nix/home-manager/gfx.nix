{
  lib,
  pkgs ? null,
  systemInfo ? null,
  ...
}:
let
  requirePkgs = if pkgs == null then throw "gfx: pkgs is required" else pkgs;
  requireSystemInfo = if systemInfo == null then throw "gfx: systemInfo is required" else systemInfo;

  gbmPaths = lib.unique [
    "/usr/lib64/gbm"
    "/usr/lib/gbm"
    "/run/opengl-driver/lib/gbm"
    "/run/opengl-driver-32/lib/gbm"
  ];

  driPaths = lib.unique [
    "/usr/lib64/dri"
    "/usr/lib/dri"
    "/run/opengl-driver/lib/dri"
    "/run/opengl-driver-32/lib/dri"
  ];

  eglVendorPaths = lib.unique [
    "/usr/share/glvnd/egl_vendor.d"
    "/usr/local/share/glvnd/egl_vendor.d"
    "/etc/glvnd/egl_vendor.d"
  ];

  ldPaths = lib.unique [
    "/usr/lib"
    "/usr/lib64"
  ];

  gfxDriverEnv = {
    GBM_BACKENDS_PATH = lib.concatStringsSep ":" gbmPaths;
    LIBGL_DRIVERS_PATH = lib.concatStringsSep ":" driPaths;
    EGL_VENDOR_LIBRARY_DIRS = lib.concatStringsSep ":" eglVendorPaths;
    LD_LIBRARY_PATHS = lib.concatStringsSep ":" ldPaths;
  };

  # NVIDIA's libEGL_nvidia.so dlopens libnvidia-egl-wayland.so.1 and
  # libnvidia-egl-gbm.so.1 to expose the Wayland EGL and GBM platforms.
  # nixGL's NVIDIA bundle does NOT include these external platform libs,
  # so on non-NixOS hosts Nix-built Wayland clients fail with "provided
  # display handle is not supported". We add the lib paths to LD_LIBRARY_PATH
  # and register their JSON configs via __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES.
  nvidiaEglPlatformLibs = lib.optionalString requireSystemInfo.hasNvidia
    "${requirePkgs.egl-wayland}/lib:${requirePkgs.egl-gbm}/lib";

  nvidiaEglPlatformConfigs = lib.optionalString requireSystemInfo.hasNvidia
    "${requirePkgs.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json:${requirePkgs.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json";

  # Wrap a Nix-built GUI binary in nixGL and inject system driver search
  # paths (Mesa GBM backends, DRI drivers) so loaders find /usr/lib/gbm,
  # /usr/lib/dri, etc. on non-NixOS hosts. --suffix lets user-set env
  # values take precedence; missing paths in the list are silently skipped.
  mkNixGLWrapper =
    name: programPath:
    requirePkgs.runCommand name { nativeBuildInputs = [ requirePkgs.makeWrapper ]; } ''
      makeWrapper ${requireSystemInfo.nixGLBin} $out/bin/${name} \
        --suffix GBM_BACKENDS_PATH : "${gfxDriverEnv.GBM_BACKENDS_PATH}" \
        --suffix LIBGL_DRIVERS_PATH : "${gfxDriverEnv.LIBGL_DRIVERS_PATH}" \
        ${lib.optionalString requireSystemInfo.hasNvidia ''
          --suffix LD_LIBRARY_PATH : "${nvidiaEglPlatformLibs}" \
          --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${nvidiaEglPlatformConfigs}" \
        ''}--add-flag "${programPath}"
    '';

  # Direct wrapper without nixGL - for DRM/KMS mode where we need host EGL
  mkDirectWrapperWithDrivers =
    name: programPath:
    requirePkgs.runCommand name { nativeBuildInputs = [ requirePkgs.makeWrapper ]; } ''
      makeWrapper ${programPath} $out/bin/${name} \
        --set GBM_BACKENDS_PATH "${gfxDriverEnv.GBM_BACKENDS_PATH}" \
        --set LIBGL_DRIVERS_PATH "${gfxDriverEnv.LIBGL_DRIVERS_PATH}" \
        --set __EGL_VENDOR_LIBRARY_DIRS "${gfxDriverEnv.EGL_VENDOR_LIBRARY_DIRS}" \
        --set LD_LIBRARY_PATH "${gfxDriverEnv.LD_LIBRARY_PATHS}" \
        --unset __EGL_VENDOR_LIBRARY_FILENAMES
    '';
in
{
  gfx =
    program:
    let
      programPath = lib.getExe program;
      name = builtins.baseNameOf programPath;
    in
    mkNixGLWrapper name programPath;

  gfxName = name: program: mkNixGLWrapper name (lib.getExe program);

  gfxExe =
    exeName: program:
    let
      programPath = lib.getExe' program exeName;
      name = builtins.baseNameOf programPath;
    in
    mkNixGLWrapper name programPath;

  gfxDirectWithDrivers = name: program: mkDirectWrapperWithDrivers name (lib.getExe program);
}
