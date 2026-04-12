_: {
  enableIf = { config, ... }: config.features.vpn;
  args =
    { config, ... }:
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
        // managed-by: home-manager vpn-polkit v1
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.policykit.exec" &&
              subject.user == "${config.home.username}") {
            var program = action.lookup("program");
            var commandLine = action.lookup("command_line");
            var allowed = [
              "/usr/bin/openconnect",
              "${config.home.homeDirectory}/.nix-profile/bin/openconnect",
              "/bin/pkill",
              "/usr/bin/pkill",
              "${config.home.homeDirectory}/.nix-profile/bin/pkill",
              "/bin/setsid",
              "/usr/bin/setsid",
              "${config.home.homeDirectory}/.nix-profile/bin/setsid"
            ];
            var cmdAllowed = function(cmdline) {
              if (!cmdline) return false;
              for (var i = 0; i < allowed.length; i++) {
                if (cmdline.indexOf(allowed[i]) == 0) {
                  return true;
                }
              }
              return false;
            };

            if ((program && allowed.indexOf(program) !== -1) || cmdAllowed(commandLine)) {
              return polkit.Result.YES;
            }
          }
        });
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
