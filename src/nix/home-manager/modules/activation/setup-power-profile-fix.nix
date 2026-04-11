_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupPowerProfileFix";
  activationName = "setupPowerProfileFix";
  scriptName = "setup-power-profile-fix";
  after = order.after.setupPowerProfileFix;
  enableIf = { config, ... }: config.features.desktop;
  sudoArgs =
    { config, ... }:
    let
      rulePath = "/etc/polkit-1/rules.d/50-power-profile-fix.rules";
      stateDir = config.xdg.stateHome or "${config.home.homeDirectory}/.local/state";
      hashPath = "${stateDir}/power-profile-fix/polkit-hash";
      ruleContent = ''
        // managed-by: home-manager power-profile-fix v2
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.policykit.exec" &&
              subject.user == "${config.home.username}") {
            var program = action.lookup("program");

            // Allow the power-profile-helper script to run
            if (program && program.indexOf("power.profile.helper.sh") !== -1) {
              return polkit.Result.YES;
            }
          }
        });
      '';
    in
    {
      preCheck = ''
              expected_hash="${builtins.hashString "sha256" ruleContent}"
              if [ -f "${hashPath}" ] && [ "$(cat "${hashPath}")" = "$expected_hash" ]; then
                exit 0
              fi
      '';
      promptTitle = "Installing polkit rule for CPU frequency scaling fix";
      promptBody = ''
        echo "This allows ${config.home.username} to adjust CPU energy performance"
        echo "preferences when power profile changes, fixing the 400MHz lock issue."
      '';
      promptQuestion = "Install power profile fix polkit rule?";
      actionScript = ''
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' EXIT
        cat > "$tmpfile" <<'POLKIT_EOF'
${ruleContent}
POLKIT_EOF
        sudo install -m 0644 "$tmpfile" "${rulePath}"
        if getent group polkitd >/dev/null 2>&1; then
          sudo chown root:polkitd "${rulePath}"
        else
          sudo chown root:root "${rulePath}"
        fi

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl restart polkit.service >/dev/null 2>&1 || true
        fi

        mkdir -p "${stateDir}/power-profile-fix"
        echo -n "$expected_hash" > "${hashPath}"
      '';
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
