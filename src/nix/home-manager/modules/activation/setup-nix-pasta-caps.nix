_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupNixPastaCaps";
  activationName = "setupNixPastaCaps";
  scriptName = "setup-nix-pasta-caps";
  after = order.after.setupNixPastaCaps;
  sudoArgs =
    _:
    let
      nixConf = "/etc/nix/nix.conf";
      systemPasta = "/usr/bin/pasta";
    in
    {
      preCheck = ''
        if grep -q "^pasta-path = ${systemPasta}" "${nixConf}" 2>/dev/null; then
          exit 0
        fi
      '';
      promptTitle = "Nix sandbox networking fix required";
      promptBody = ''
        echo "The nix-daemon is configured to use a pasta binary in the nix store"
        echo "which cannot have capabilities set on it, causing sandbox network"
        echo "timeouts. This adds 'pasta-path = ${systemPasta}' to ${nixConf}"
        echo "so the daemon uses the system pasta binary instead."
      '';
      promptQuestion = "Set pasta-path in ${nixConf}?";
      actionScript = ''
        # Remove any existing pasta-path line and append the correct one
        sudo sed -i '/^pasta-path/d' "${nixConf}"
        echo "pasta-path = ${systemPasta}" | sudo tee -a "${nixConf}" > /dev/null
        sudo systemctl restart nix-daemon.service
        echo "Done. nix-daemon restarted with system pasta."
      '';
      skipMessage = "Skipped. Sandbox network builds may fail. Run: home-manager switch --flake . --impure";
    };
}
