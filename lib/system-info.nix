{ pkgs }:
let
  hasNvidia = builtins.pathExists (/. + "/proc/driver/nvidia/version");

  # `nixgl.nixGLNvidia` only exists when the overlay's eval-time version
  # detection succeeded (modules/overlays.nix reads /proc with
  # builtins.readFile, which returns "" on kernels that report the file
  # as zero-sized). Fall back to nixGL's `auto` set, which copies
  # /proc/driver/nvidia/version in a runCommand and so always detects.
  nixGLWrapper =
    if hasNvidia then
      (pkgs.nixgl.nixGLNvidia or pkgs.nixgl.auto.nixGLNvidia)
    else
      pkgs.nixgl.nixGLIntel;
  nixGLBin = "${nixGLWrapper}/bin/${nixGLWrapper.name}";
in
{
  inherit hasNvidia nixGLWrapper nixGLBin;
}
