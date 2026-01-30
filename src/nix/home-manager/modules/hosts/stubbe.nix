{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module = {
      imports = [
        hm.context
        hm.targets
        hm.base
        hm.packages.cli
        hm.packages.development
        hm.packages.system
        hm.packages.nixTools
        hm.packages.security
        hm.packages.media
        hm.packages.hyprland
        hm.packages.theming
        hm.packages.hm
        hm.themeDconf
        hm.themeGtk
        hm.themeQt
        hm.themeFiles
        hm.themeFlatpak
        hm.themeSessionVariables
        hm.files
        hm.sessionVariables
        hm.activation.customBinInstall
        hm.activation.customShellCompletions
        hm.activation.customConfigCleanUp
        hm.activation.setupPamWrappers
        hm.activation.setupHyprlockPam
        hm.activation.setupHyprKeyringPam
        hm.activation.setupHyprSession
        hm.activation.setupSnapThemes
        hm.activation.setupVpnPolkit
        hm.activation.setupPowerProfileFix
        hm.activation.setupGrubIntelPstate
        hm.activation.restartWaybar
        hm.programs.git
        hm.programs.go
        hm.programs.uv
        hm.programs.vifm
        hm.xdgBase
        hm.xdgHypr
        hm.xdgOpencode
        hm.xdgAerc
        hm.xdgAudio
        hm.xdgPortal
        hm.xdgKde
        hm.xdgVpn
        hm.systemd
        hm.nix
      ];
    };
  };
}
