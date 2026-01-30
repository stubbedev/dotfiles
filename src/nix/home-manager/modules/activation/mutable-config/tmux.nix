{ ... }:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigTmux";
  activationName = "applyMutableConfigTmux";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.desktop;
  script = { config, pkgs, ... }: ''
    mkdir -p "${config.home.homeDirectory}/.tmux/plugins"
    if [ ! -d "${config.home.homeDirectory}/.tmux/plugins/tpm" ]; then
      ${pkgs.git}/bin/git clone --quiet https://github.com/tmux-plugins/tpm ${config.home.homeDirectory}/.tmux/plugins/tpm
    fi
  '';
}
