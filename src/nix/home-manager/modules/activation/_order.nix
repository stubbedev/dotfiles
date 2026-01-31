{
  steps = {
    shellCompletions = "customShellCompletions";
    mutableConfig = "customConfigCleanUp";
    setupPamWrappers = "setupPamWrappers";
    setupHyprlockPam = "setupHyprlockPam";
    setupHyprKeyringPam = "setupHyprlockPam";
    setupHyprSession = "setupHyprKeyringPam";
    setupGreetd = "setupGreetd";
    setupConsoleFont = "setupConsoleFont";
    setupSnapThemes = "setupSnapThemes";
    setupVpnPolkit = "setupVpnPolkit";
    setupPowerProfileFix = "setupPowerProfileFix";
    setupGrubIntelPstate = "setupGrubIntelPstate";
    restartWaybar = "restartWaybar";
  };

  after = {
    shellCompletions = [ "writeBoundary" ];
    mutableConfig = [ "customShellCompletions" ];
    setupPamWrappers = [ "customConfigCleanUp" ];
    setupHyprlockPam = [ "setupPamWrappers" ];
    setupHyprKeyringPam = [ "setupHyprlockPam" ];
    setupHyprSession = [ "setupHyprKeyringPam" ];
    setupGreetd = [ "setupHyprSession" ];
    setupConsoleFont = [ "setupGreetd" ];
    setupSnapThemes = [ "setupConsoleFont" ];
    setupVpnPolkit = [ "setupSnapThemes" ];
    setupPowerProfileFix = [ "setupVpnPolkit" ];
    setupGrubIntelPstate = [ "setupPowerProfileFix" ];
    restartWaybar = [ "setupGrubIntelPstate" ];
  };
}
