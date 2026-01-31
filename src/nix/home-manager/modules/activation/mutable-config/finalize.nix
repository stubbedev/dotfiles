_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
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
    "applyMutableConfigZsh"
  ];
  enableIf = { config, ... }: config.features.desktop;
  script = "";
}
