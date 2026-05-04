{
  lib,
  pkgs,
}:
let
  # Convert string path to path type
  stringToPath = path: if builtins.isPath path then path else /. + path;

  nvidiaVersionPath = "/proc/driver/nvidia/version";
  hasNvidia = builtins.pathExists (stringToPath nvidiaVersionPath);

  osReleasePath = "/etc/os-release";
  osReleaseContent =
    if builtins.pathExists (stringToPath osReleasePath) then
      builtins.readFile (stringToPath osReleasePath)
    else
      "";
  isFedora = builtins.match ".*ID=fedora.*" osReleaseContent != null;

  nixGLWrapper = if hasNvidia then pkgs.nixgl.nixGLNvidia else pkgs.nixgl.nixGLIntel;
  nixGLBin = "${nixGLWrapper}/bin/${nixGLWrapper.name}";
in
{
  inherit hasNvidia isFedora;
  libPath = if isFedora then "lib64" else "lib";
  inherit nixGLWrapper nixGLBin;
}
