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
        hm.packagesCli
        hm.packagesDevelopment
        hm.packagesSystem
        hm.packagesNixTools
        hm.packagesSecurity
        hm.packagesMedia
        hm.packagesHyprland
        hm.packagesTheming
        hm.packagesHm
        hm.themeDconf
        hm.themeGtk
        hm.themeQt
        hm.themeFiles
        hm.themeFlatpak
        hm.themeSessionVariables
        hm.files
        hm.sessionVariables
        hm.activationSetupShellCompletions
        hm.activationApplyMutableConfig
        hm.activationSetupPamWrappers
        hm.activationSetupHyprlockPam
        hm.activationSetupHyprKeyringPam
        hm.activationSetupHyprSession
        hm.activationSetupSnapThemes
        hm.activationSetupVpnPolkit
        hm.activationSetupPowerProfileFix
        hm.activationSetupGrubIntelPstate
        hm.activationRestartServiceWaybar
        hm.programsGit
        hm.programsGo
        hm.programsUv
        hm.programsVifm
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
