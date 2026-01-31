_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigLazygit";
  activationName = "applyMutableConfigLazygit";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script =
    {
      config,
      pkgs,
      ...
    }:
    ''
      mkdir -p "${config.home.homeDirectory}/.config/lazygit"
      cat "${config.home.homeDirectory}/.stubbe/src/lazygit/state.yml" > "${config.home.homeDirectory}/.config/lazygit/state.yml"
      echo "lastversion: ${pkgs.lazygit.version}" >> "${config.home.homeDirectory}/.config/lazygit/state.yml"
    '';
}
