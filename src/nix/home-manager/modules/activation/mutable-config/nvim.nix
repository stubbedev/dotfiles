_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigNvim";
  activationName = "applyMutableConfigNvim";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script =
    { config, ... }:
    ''
      rm -rf "${config.home.homeDirectory}/.config/nvim"
      ln -sf "${config.home.homeDirectory}/.stubbe/src/nvim" "${config.home.homeDirectory}/.config/nvim"
    '';
}
