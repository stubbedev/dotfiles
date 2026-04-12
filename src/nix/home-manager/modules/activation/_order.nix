{
  steps = {
    shellCompletions = "customShellCompletions";
    mutableConfig = "customConfigCleanUp";
    setupPamWrappers = "setupPamWrappers";
    setupHyprlockPam = "setupHyprlockPam";
    setupHyprKeyringPam = "setupHyprlockPam";
    setupHyprSession = "setupHyprKeyringPam";
    setupNiriKeyringPam = "setupNiriKeyringPam";
    setupNiriSession = "setupNiriSession";
    setupSnapThemes = "setupSnapThemes";
    setupVpnPolkit = "setupVpnPolkit";
    setupPowerProfileFix = "setupPowerProfileFix";
    setupGrubIntelPstate = "setupGrubIntelPstate";
    setupNodeCaBundle = "setupNodeCaBundle";
    setupOxcTools = "setupOxcTools";
    setupPrettier = "setupPrettier";
    restartWaybar = "restartWaybar";
  };

  after = {
    shellCompletions = [ "writeBoundary" ];
    mutableConfig = [ "customShellCompletions" ];
    setupPamWrappers = [ "customConfigCleanUp" ];
    setupHyprlockPam = [ "setupPamWrappers" ];
    setupHyprKeyringPam = [ "setupHyprlockPam" ];
    setupHyprSession = [ "setupHyprKeyringPam" ];
    setupNiriKeyringPam = [ "setupPamWrappers" ];
    setupNiriSession = [ "setupNiriKeyringPam" ];
    setupSnapThemes = [ "setupHyprSession" ];
    setupVpnPolkit = [ "setupSnapThemes" ];
    setupPowerProfileFix = [ "setupVpnPolkit" ];
    setupGrubIntelPstate = [ "setupPowerProfileFix" ];
    setupNodeCaBundle = [ "writeBoundary" ];
    setupOxcTools = [ "writeBoundary" ];
    setupPrettier = [ "writeBoundary" ];
    restartWaybar = [ "setupGrubIntelPstate" ];
  };
}
