_:
let
  helpers = import ../_helpers.nix;
  order = import ../_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationApplyMutableConfigOpenCode";
  activationName = "applyMutableConfigOpenCode";
  after = order.after.mutableConfig;
  enableIf = { config, ... }: config.features.opencode;
  script =
    { config, ... }:
    ''
      if [ -f "${config.home.homeDirectory}/.local/share/opencode/opencode.db" ]; then
        ln -s "${config.home.homeDirectory}/.local/share/opencode/opencode-local.db" "${config.home.homeDirectory}/.local/share/opencode/opencode.db" 2>&1 >/dev/null
      fi
    '';
}
