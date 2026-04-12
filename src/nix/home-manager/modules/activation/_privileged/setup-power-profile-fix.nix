_: {
  moduleName = "activationSetupPowerProfileFix";
  activationName = "setupPowerProfileFix";
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      promptTitle = "Installing polkit rule for CPU frequency scaling fix";
      promptBody = ''
        This allows ${config.home.username} to adjust CPU energy performance
        preferences when power profile changes, fixing the 400MHz lock issue.
      '';
      promptQuestion = "Install power profile fix polkit rule?";
      actionScript = ''
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' EXIT
        cat > "$tmpfile" << 'EOF'
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
        EOF
        sudo install -m 0644 "$tmpfile" /etc/polkit-1/rules.d/50-power-profile-fix.rules
        if getent group polkitd >/dev/null 2>&1; then
          sudo chown root:polkitd /etc/polkit-1/rules.d/50-power-profile-fix.rules
        else
          sudo chown root:root /etc/polkit-1/rules.d/50-power-profile-fix.rules
        fi
        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl restart polkit.service >/dev/null 2>&1 || true
        fi
      '';
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
