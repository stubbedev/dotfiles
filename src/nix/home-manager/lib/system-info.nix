{ lib, pkgs }:
let
  toPath = path:
    if builtins.isPath path then
      path
    else
      /. + path;

  nvidiaVersionPath = "/proc/driver/nvidia/version";
  hasNvidia = builtins.pathExists (toPath nvidiaVersionPath);

  osReleasePath = "/etc/os-release";
  osReleaseContent =
    if builtins.pathExists (toPath osReleasePath) then
      builtins.readFile (toPath osReleasePath)
    else
      "";
  isFedora = builtins.match ".*ID=fedora.*" osReleaseContent != null;
in
{
  inherit hasNvidia isFedora;
  libPath = if isFedora then "lib64" else "lib";
  nixGLWrapper = if hasNvidia then pkgs.nixgl.nixGLNvidia else pkgs.nixgl.nixGLIntel;
}
