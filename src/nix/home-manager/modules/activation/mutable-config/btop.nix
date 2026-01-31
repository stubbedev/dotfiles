_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigBtop";
  activationName = "applyMutableConfigBtop";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script =
    { config, ... }:
    ''
      mkdir -p "${config.home.homeDirectory}/.config/btop"
      cat "${config.home.homeDirectory}/.stubbe/src/btop/btop.conf" > "${config.home.homeDirectory}/.config/btop/btop.conf"
    '';
}
