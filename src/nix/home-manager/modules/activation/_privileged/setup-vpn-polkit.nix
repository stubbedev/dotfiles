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
        // managed-by: home-manager vpn-polkit v2
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

          var openconnectPrograms = [
            "/usr/bin/openconnect",
            "/bin/openconnect",
            "/run/current-system/sw/bin/openconnect",
            "${config.home.homeDirectory}/.nix-profile/bin/openconnect"
          ];
          var pkillPrograms = [
            "/usr/bin/pkill",
            "/bin/pkill",
            "/run/current-system/sw/bin/pkill",
            "${config.home.homeDirectory}/.nix-profile/bin/pkill"
          ];
          var setsidPrograms = [
            "/usr/bin/setsid",
            "/bin/setsid",
            "/run/current-system/sw/bin/setsid",
            "${config.home.homeDirectory}/.nix-profile/bin/setsid"
          ];

          var splitArgs = function(cmdline) {
            if (!cmdline) {
              return [];
            }
            return cmdline.trim().split(/\s+/);
          };

          var pathAllowed = function(path, allowed) {
            return allowed.indexOf(path) !== -1;
          };

          var isPidFilePath = function(path) {
            return /^\/run\/user\/[0-9]+\/openconnect-[A-Za-z0-9_.-]+\.pid$/.test(path);
          };

          var validateOpenconnectCommand = function(args, execIndex) {
            var i = execIndex + 1;
            var hasProtocol = false;
            var hasUser = false;
            var hasCookie = false;
            var hasInterface = false;
            var hasPidFile = false;
            var hasSyslog = false;
            var hasBackground = false;
            var hostCount = 0;

            while (i < args.length) {
              var token = args[i];

              if (token === "--protocol=gp") {
                hasProtocol = true;
                i += 1;
                continue;
              }
              if (token === "--syslog") {
                hasSyslog = true;
                i += 1;
                continue;
              }
              if (token === "--background") {
                hasBackground = true;
                i += 1;
                continue;
              }

              if (token === "--user" || token === "--cookie" || token === "--interface" || token === "--pid-file" || token === "--servercert") {
                if (i + 1 >= args.length) {
                  return false;
                }
                var value = args[i + 1];
                if (!/^\S+$/.test(value)) {
                  return false;
                }

                if (token === "--user") {
                  hasUser = true;
                } else if (token === "--cookie") {
                  hasCookie = true;
                } else if (token === "--interface") {
                  if (!/^[A-Za-z0-9_.:-]+$/.test(value)) {
                    return false;
                  }
                  hasInterface = true;
                } else if (token === "--pid-file") {
                  if (!isPidFilePath(value)) {
                    return false;
                  }
                  hasPidFile = true;
                }

                i += 2;
                continue;
              }

              if (token.indexOf("--servercert=") === 0) {
                var certValue = token.substring("--servercert=".length);
                if (!/^\S+$/.test(certValue)) {
                  return false;
                }
                i += 1;
                continue;
              }

              if (token.indexOf("--") === 0) {
                return false;
              }

              if (!/^\S+$/.test(token) || token[0] === "-") {
                return false;
              }
              hostCount += 1;
              i += 1;
            }

            return hasProtocol && hasUser && hasCookie && hasInterface && hasPidFile && hasSyslog && hasBackground && hostCount === 1;
          };

          var args = splitArgs(commandLine);
          if (args.length === 0 || args[0] !== program) {
            return;
          }

          if (pathAllowed(program, openconnectPrograms) && validateOpenconnectCommand(args, 0)) {
            return polkit.Result.YES;
          }

          if (pathAllowed(program, pkillPrograms)) {
            if (args.length === 3 && args[1] === "-F" && isPidFilePath(args[2])) {
              return polkit.Result.YES;
            }
            if (args.length === 3 && args[1] === "-f" && /^openconnect\.\*[A-Za-z0-9_.-]+$/.test(args[2])) {
              return polkit.Result.YES;
            }
            return;
          }

          if (pathAllowed(program, setsidPrograms)) {
            if (args.length >= 2 && pathAllowed(args[1], openconnectPrograms) && validateOpenconnectCommand(args, 1)) {
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
