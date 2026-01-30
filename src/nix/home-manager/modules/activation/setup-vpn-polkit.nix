{ ... }:
let
  helpers = import ./_helpers.nix;
in
helpers.mkSudoSetupModule {
  name = "setupVpnPolkit";
  scriptName = "setup-vpn-polkit";
  after = [ "setupSnapThemes" ];
  sudoArgs = { config, ... }:
    let
      rulePath = "/etc/polkit-1/rules.d/49-openconnect.rules";
      stateDir = config.xdg.stateHome or "${config.home.homeDirectory}/.local/state";
      stampPath = "${stateDir}/vpn/polkit-installed";
      ruleContent = ''
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
      '';
    in
    {
      preCheck = ''
        if [ -f "${stampPath}" ]; then
          exit 0
        fi

        if [ -r "${rulePath}" ] && grep -q "managed-by: home-manager vpn-polkit v1" "${rulePath}"; then
          mkdir -p "${stateDir}/vpn"
          touch "${stampPath}"
          exit 0
        fi

        if sudo -n test -f "${rulePath}" 2>/dev/null; then
          if sudo -n grep -q "managed-by: home-manager vpn-polkit v1" "${rulePath}"; then
            mkdir -p "${stateDir}/vpn"
            touch "${stampPath}"
            exit 0
          fi
        fi

        tmpfile=$(mktemp)
        cat > "$tmpfile" <<'EOF'
${ruleContent}
EOF
      '';
      promptTitle = "Installing polkit rule for VPN (passwordless pkexec)";
      promptBody = ''
        echo "This allows ${config.home.username} to run openconnect/pkill via pkexec"
        echo "without a password prompt."
      '';
      promptQuestion = "Install VPN polkit rule?";
      actionScript = ''
        sudo install -m 0644 "$tmpfile" "${rulePath}"
        if getent group polkitd >/dev/null 2>&1; then
          sudo chown root:polkitd "${rulePath}"
        else
          sudo chown root:root "${rulePath}"
        fi
        rm -f "$tmpfile"

        mkdir -p "${stateDir}/vpn"
        touch "${stampPath}"

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl restart polkit.service >/dev/null 2>&1 || true
        fi
      '';
      skipMessage =
        "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
