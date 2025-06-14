{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    package = pkgs.steam;
    steamRuntime = true;
  };
}
