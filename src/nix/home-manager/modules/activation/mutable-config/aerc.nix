_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigAerc";
  activationName = "applyMutableConfigAerc";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script =
    { config, ... }:
    ''
      mkdir -p "${config.home.homeDirectory}/.config/aerc"
      rm -rf "${config.home.homeDirectory}/.config/aerc/stylesets"
      ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/stylesets" "${config.home.homeDirectory}/.config/aerc/stylesets"
      rm -rf "${config.home.homeDirectory}/.config/aerc/accounts"
      ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/accounts" "${config.home.homeDirectory}/.config/aerc/accounts"
      rm -rf "${config.home.homeDirectory}/.config/aerc/accounts.conf"
      ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/accounts.conf" "${config.home.homeDirectory}/.config/aerc/accounts.conf"
      chmod 600 "${config.home.homeDirectory}/.stubbe/src/aerc/accounts.conf"
    '';
}
