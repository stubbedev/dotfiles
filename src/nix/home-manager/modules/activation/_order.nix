{
  steps = {
    shellCompletions = "customShellCompletions";
    mutableConfig = "customConfigCleanUp";
    setupPamWrappers = "setupPamWrappers";
    setupHyprlockPam = "setupHyprlockPam";
    setupHyprKeyringPam = "setupHyprlockPam";
    setupHyprSession = "setupHyprKeyringPam";
    setupSnapThemes = "setupSnapThemes";
    setupVpnPolkit = "setupVpnPolkit";
    setupPowerProfileFix = "setupPowerProfileFix";
    setupGrubIntelPstate = "setupGrubIntelPstate";
    setupNodeCaBundle = "setupNodeCaBundle";
    restartWaybar = "restartWaybar";
  };

  after = {
    shellCompletions = [ "writeBoundary" ];
    mutableConfig = [ "customShellCompletions" ];
    setupPamWrappers = [ "customConfigCleanUp" ];
    setupHyprlockPam = [ "setupPamWrappers" ];
    setupHyprKeyringPam = [ "setupHyprlockPam" ];
    setupHyprSession = [ "setupHyprKeyringPam" ];
    setupSnapThemes = [ "setupHyprSession" ];
    setupVpnPolkit = [ "setupSnapThemes" ];
    setupPowerProfileFix = [ "setupVpnPolkit" ];
    setupGrubIntelPstate = [ "setupPowerProfileFix" ];
    setupNodeCaBundle = [ "writeBoundary" ];
    restartWaybar = [ "setupGrubIntelPstate" ];
  };
}
