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

  gfxDriverEnv = {
    GBM_BACKENDS_PATH = lib.concatStringsSep ":" gbmPaths;
    LIBGL_DRIVERS_PATH = lib.concatStringsSep ":" driPaths;
  };

  mkNixGLWrapper = name: programPath:
    requirePkgs.runCommand name { nativeBuildInputs = [ requirePkgs.makeWrapper ]; } ''
      makeWrapper ${requireSystemInfo.nixGLBin} $out/bin/${name} \
        --add-flag "${programPath}"
    '';

  mkNixGLWrapperWithDrivers = name: programPath:
    requirePkgs.runCommand name { nativeBuildInputs = [ requirePkgs.makeWrapper ]; } ''
      makeWrapper ${requireSystemInfo.nixGLBin} $out/bin/${name} \
        --set GBM_BACKENDS_PATH "${gfxDriverEnv.GBM_BACKENDS_PATH}" \
        --set LIBGL_DRIVERS_PATH "${gfxDriverEnv.LIBGL_DRIVERS_PATH}" \
        --add-flag "${programPath}"
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
  gfxBinIncDrivers =
    name: program:
    mkNixGLWrapperWithDrivers name (lib.getExe program);
  gfxExe =
    exeName: program:
    let
      programPath = lib.getExe' program exeName;
      name = builtins.baseNameOf programPath;
    in
    mkNixGLWrapper name programPath;
  gfxBinExeIncDrivers =
    exeName: program:
    let
      programPath = lib.getExe' program exeName;
      name = builtins.baseNameOf programPath;
    in
    mkNixGLWrapperWithDrivers name programPath;
  gfxNameExe =
    name: exeName: program:
    mkNixGLWrapper name (lib.getExe' program exeName);
  gfxList =
    programs:
    map (
      program:
      let
        programPath = lib.getExe program;
        name = builtins.baseNameOf programPath;
      in
      mkNixGLWrapper name programPath
    ) programs;
}
