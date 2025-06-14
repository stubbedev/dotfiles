{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    package = pkgs.steam;
    steamRuntime = true;
    steamRuntimePackages = with pkgs; [
      libglvnd
      libglvnd.dev
      libglvnd.libGL
      libglvnd.libEGL
      libglvnd.libGLESv2
      libglvnd.libGLESv1_CM
      libglvnd.libOpenGL
      nss
      nss.dev
      nss.p11-kit
      nss.p11-kit-trust
    ];
  };
}
