{ self, ... }:
{
  enableIf = { config, ... }: config.features.vpn;
  args =
    { config, ... }:
    let
      ruleContent = builtins.replaceStrings
        [ "@USERNAME@" "@HOME@" ]
        [ config.home.username config.home.homeDirectory ]
        (builtins.readFile (self + "/src/polkit/49-openconnect.rules"));
    in
    {
      promptTitle = "Installing polkit rule for VPN (passwordless pkexec)";
      promptBody = ''
        This allows ${config.home.username} to run openconnect/pkill via pkexec
        without a password prompt.
      '';
      promptQuestion = "Install VPN polkit rule?";
      actionScript = ''
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' EXIT
        cat > "$tmpfile" << 'EOF'
        ${ruleContent}
        EOF
        sudo install -m 0644 "$tmpfile" /etc/polkit-1/rules.d/49-openconnect.rules
        if getent group polkitd >/dev/null 2>&1; then
          sudo chown root:polkitd /etc/polkit-1/rules.d/49-openconnect.rules
        else
          sudo chown root:root /etc/polkit-1/rules.d/49-openconnect.rules
        fi
        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl restart polkit.service >/dev/null 2>&1 || true
        fi
      '';
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
