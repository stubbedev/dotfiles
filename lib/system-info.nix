{ pkgs }:
let
  hasNvidia = builtins.pathExists (/. + "/proc/driver/nvidia/version");

  nixGLWrapper = if hasNvidia then pkgs.nixgl.nixGLNvidia else pkgs.nixgl.nixGLIntel;
  nixGLBin = "${nixGLWrapper}/bin/${nixGLWrapper.name}";
in
{
  inherit hasNvidia nixGLWrapper nixGLBin;
}
