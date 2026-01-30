{ inputs, ... }:
{
  flake.modules.homeManager.context = { config, lib, pkgs, ... }:
    let
      constants = import ../../constants.nix { inherit config; };

      # Auto-detect system information
      hasNvidia =
        builtins.pathExists (homeLib.toPath "/proc/driver/nvidia/version");

      # Detect OS distribution
      osReleasePath = /etc/os-release;
      osReleaseContent =
        if builtins.pathExists osReleasePath then
          builtins.readFile osReleasePath
        else
          "";
      isFedora = builtins.match ".*ID=fedora.*" osReleaseContent != null;

      # System-specific library paths and nixGL wrapper selection
      systemInfo = {
        inherit hasNvidia isFedora;
        libPath = if isFedora then "lib64" else "lib";
        # Select the appropriate nixGL wrapper based on GPU detection
        nixGLWrapper =
          if hasNvidia then pkgs.nixgl.nixGLNvidia else pkgs.nixgl.nixGLIntel;
      };

      homeLib = import ../../lib.nix { inherit lib pkgs systemInfo; };

      # Load VPN scripts/config dynamically
      vpnConfigs = homeLib.loadVpnConfigs ../../../../vpn;
      vpnScripts = homeLib.loadVpnScripts ../../../../vpn;
    in
    {
      _module.args = {
        inherit constants systemInfo homeLib vpnConfigs vpnScripts;
        inherit (inputs) hyprland hy3;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
      };
    };
}
