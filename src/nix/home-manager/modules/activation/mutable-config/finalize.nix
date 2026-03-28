_:
let
  helpers = import ../_helpers.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigFinalize";
  activationName = "customConfigCleanUp";
  after = [
    "applyMutableConfigNvim"
    "applyMutableConfigTmux"
    "applyMutableConfigLazygit"
    "applyMutableConfigBtop"
    "applyMutableConfigAerc"
    "applyMutableConfigOpenCode"
    "applyMutableConfigZsh"
  ];
  enableIf = { config, ... }: config.features.desktop;
  script = "";
}
