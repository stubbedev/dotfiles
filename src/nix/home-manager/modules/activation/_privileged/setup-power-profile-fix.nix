_: {
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
        // managed-by: home-manager power-profile-fix v3
        polkit.addRule(function(action, subject) {
          if (action.id !== "org.freedesktop.policykit.exec") {
            return;
          }
          if (subject.user !== "${config.home.username}" || !subject.local || !subject.active) {
            return;
          }

          var program = action.lookup("program");
          var commandLine = action.lookup("command_line");
          if (!program || !commandLine) {
            return;
          }

          var allowedPrograms = [
            "${config.home.homeDirectory}/.stubbe/src/hypr/scripts/power.profile.helper.sh"
          ];
          if (allowedPrograms.indexOf(program) === -1) {
            return;
          }

          var args = commandLine.trim().split(/\s+/);
          if (args.length < 2 || args[0] !== program) {
            return;
          }

          var isIntInRange = function(value, min, max) {
            if (!/^[0-9]+$/.test(value)) {
              return false;
            }
            var n = Number(value);
            return n >= min && n <= max;
          };

          var mode = args[1];
          if (mode === "set-governor") {
            if (args.length === 3 && (args[2] === "schedutil" || args[2] === "performance")) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-epp") {
            if (args.length === 3 && (args[2] === "power" || args[2] === "balance_power" || args[2] === "balance_performance" || args[2] === "performance")) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-pstate-limits") {
            if (args.length === 4 && isIntInRange(args[2], 0, 100) && isIntInRange(args[3], 0, 100) && Number(args[2]) <= Number(args[3])) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-policy-freqs") {
            if (args.length === 4 && isIntInRange(args[2], 0, 100) && isIntInRange(args[3], 0, 100) && Number(args[2]) <= Number(args[3])) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-policy-min") {
            if (args.length === 3 && isIntInRange(args[2], 0, 100)) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-schedutil") {
            if (
              args.length === 5 &&
              isIntInRange(args[2], 0, 1000000) &&
              isIntInRange(args[3], 0, 1000000) &&
              (args[4] === "0" || args[4] === "1")
            ) {
              return polkit.Result.YES;
            }
            return;
          }

          if (mode === "set-boost") {
            if (args.length === 3 && (args[2] === "0" || args[2] === "1")) {
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
