{
  lib,
  pkgs,
  systemInfo,
  isNixOS ? false,
  ...
}:
let
  # Mesa probes these paths literally — non-existent entries are skipped,
  # but if none exist EGL/GBM init fails. Cover RHEL/Arch (lib64), generic
  # (lib), and Debian/Ubuntu multiarch (lib/x86_64-linux-gnu) layouts.
  gbmPaths = lib.unique [
    "/usr/lib/x86_64-linux-gnu/gbm"
    "/usr/lib64/gbm"
    "/usr/lib/gbm"
    "/run/opengl-driver/lib/gbm"
    "/run/opengl-driver-32/lib/gbm"
  ];

  driPaths = lib.unique [
    "/usr/lib/x86_64-linux-gnu/dri"
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
  nvidiaEglPlatformLibs = lib.optionalString systemInfo.hasNvidia "${pkgs.egl-wayland}/lib:${pkgs.egl-gbm}/lib";

  nvidiaEglPlatformConfigs = lib.optionalString systemInfo.hasNvidia "${pkgs.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json:${pkgs.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json";

  # Wrap a Nix-built GUI binary in nixGL and inject system driver search
  # paths (Mesa GBM backends, DRI drivers) so loaders find /usr/lib/gbm,
  # /usr/lib/dri, etc. on non-NixOS hosts. --suffix lets user-set env
  # values take precedence; missing paths in the list are silently skipped.
  mkNixGLWrapper =
    name: programPath:
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      makeWrapper ${systemInfo.nixGLBin} $out/bin/${name} \
        --suffix GBM_BACKENDS_PATH : "${gfxDriverEnv.GBM_BACKENDS_PATH}" \
        --suffix LIBGL_DRIVERS_PATH : "${gfxDriverEnv.LIBGL_DRIVERS_PATH}" \
        ${lib.optionalString systemInfo.hasNvidia ''
          --suffix LD_LIBRARY_PATH : "${nvidiaEglPlatformLibs}" \
          --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${nvidiaEglPlatformConfigs}" \
        ''}--add-flag "${programPath}"
    '';

  # Direct wrapper without nixGL - for DRM/KMS mode where we need host EGL
  mkDirectWrapperWithDrivers =
    name: programPath:
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      makeWrapper ${programPath} $out/bin/${name} \
        --set GBM_BACKENDS_PATH "${gfxDriverEnv.GBM_BACKENDS_PATH}" \
        --set LIBGL_DRIVERS_PATH "${gfxDriverEnv.LIBGL_DRIVERS_PATH}" \
        --set __EGL_VENDOR_LIBRARY_DIRS "${gfxDriverEnv.EGL_VENDOR_LIBRARY_DIRS}" \
        --set LD_LIBRARY_PATH "${gfxDriverEnv.LD_LIBRARY_PATHS}" \
        --unset __EGL_VENDOR_LIBRARY_FILENAMES
    '';
in
{
  # Wrap `program` (a package) in nixGL using its mainProgram. Output
  # name is the basename of the wrapped binary.
  gfx =
    program:
    if isNixOS then
      program
    else
      let
        programPath = lib.getExe program;
        name = baseNameOf programPath;
      in
      mkNixGLWrapper name programPath;

  # Wrap `program`'s mainProgram, exposing it under `name` (use to rename).
  gfxName =
    name: program:
    if isNixOS then
      pkgs.runCommand name { } ''
        mkdir -p $out/bin
        ln -s ${lib.getExe program} $out/bin/${name}
      ''
    else
      mkNixGLWrapper name (lib.getExe program);

  # Wrap a specific binary `exeName` from `program` (not necessarily its
  # mainProgram). Output name matches exeName.
  gfxExe =
    exeName: program:
    if isNixOS then program else mkNixGLWrapper exeName (lib.getExe' program exeName);

  # Direct (no nixGL) wrapper that injects system driver search paths.
  # For DRM/KMS contexts where we need the host's EGL implementation.
  gfxDirectWithDrivers =
    name: program:
    if isNixOS then program else mkDirectWrapperWithDrivers name (lib.getExe program);
}
