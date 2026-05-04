{ self, ... }:
{
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    let
      ruleContent = builtins.replaceStrings
        [ "@USERNAME@" "@HELPER_PATH@" ]
        [
          config.home.username
          "${config.home.homeDirectory}/.stubbe/src/_shared/scripts/power.profile.helper.sh"
        ]
        (builtins.readFile (self + "/src/polkit/50-power-profile-fix.rules"));
    in
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
        ${ruleContent}
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
