{ lib, pkgs ? null, systemInfo ? null, ... }:
let
  requirePkgs = if pkgs == null then
    throw "gfx: pkgs is required"
  else
    pkgs;
  requireSystemInfo = if systemInfo == null then
    throw "gfx: systemInfo is required"
  else
    systemInfo;

  gfxExec = programPath:
    if requireSystemInfo.hasNvidia then ''
      # NVIDIA: Find the versioned binary (e.g., nixGLNvidia-560.35.03)
      NIXGL_BIN=$(ls ${requireSystemInfo.nixGLWrapper}/bin/nixGLNvidia* 2>/dev/null | head -1)
      exec "$NIXGL_BIN" ${programPath} "$@"
    '' else ''
      # Intel/AMD: Use nixGLIntel directly
      exec ${requireSystemInfo.nixGLWrapper}/bin/nixGLIntel ${programPath} "$@"
    '';

  wrapWith = { program, name ? null, exeName ? null, prelude ? "" }:
    let
      programPath =
        if exeName == null then lib.getExe program else lib.getExe' program exeName;
      programName = if name == null then builtins.baseNameOf programPath else name;
    in
    requirePkgs.writeShellScriptBin programName (''
      # GPU detected at build time: ${if requireSystemInfo.hasNvidia then "NVIDIA" else "Intel/Mesa"}
      # Using wrapper: ${requireSystemInfo.nixGLWrapper}
    '' + prelude + (gfxExec programPath));
in {
  inherit gfxExec;

  gfx = program: wrapWith { inherit program; };
  gfxWith = prelude: program: wrapWith { inherit program prelude; };
  gfxName = name: program: wrapWith { inherit program name; };
  gfxNameWith = name: prelude: program: wrapWith { inherit program name prelude; };
  gfxExe = exeName: program: wrapWith { inherit program exeName; };
  gfxNameExe = name: exeName: program: wrapWith { inherit program name exeName; };
  gfxList = programs: map (program: wrapWith { inherit program; }) programs;
}
