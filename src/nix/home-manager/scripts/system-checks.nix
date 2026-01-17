{ config, pkgs, lib, ... }:

let
  # Define all system checks here
  checks = [{
    path = /etc/pam.d/hyprlock;
    successMessage = null; # Silent when file exists
    failureMessage = {
      title = "Hyprlock PAM configuration missing!";
      description = ''
        Hyprlock needs a PAM configuration file to authenticate passwords.
        Without this file, you won't be able to unlock your screen.'';
      solutions = [
        {
          title = "Create the file directly";
          command = ''
            sudo tee /etc/pam.d/hyprlock > /dev/null <<'EOF'
            #%PAM-1.0
            auth       include      system-auth
            account    include      system-auth
            EOF'';
        }
        {
          title = "Or symlink to existing vlock config";
          command = "sudo ln -s /etc/pam.d/vlock /etc/pam.d/hyprlock";
        }
      ];
    };
  }];

  divider =
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";

  # Format a single solution
  formatSolution = idx: sol: ''
    echo "  ${toString idx}. ${sol.title}:"
    echo "     ${lib.replaceStrings [ "\n" ] [ "\n     " ] sol.command}"
  '';

  # Format the entire failure message
  formatMessage = { title, description, solutions }:
    let
      solutionsList =
        lib.concatMapStringsSep "\n" (sol: formatSolution sol.idx sol)
        (lib.imap1 (idx: sol: sol // { inherit idx; }) solutions);
    in ''
      echo ""
      echo "${divider}"
      echo "⚠️  ${title}"
      echo "${divider}"
      echo ""
      echo "${lib.replaceStrings [ "\n" ] [ "\n" ] description}"
      echo ""
      echo "To fix this, run ONE of these commands:"
      echo ""
      ${solutionsList}
      echo ""
      echo "${divider}"
      echo ""
    '';

  # Process each check - evaluate at Nix time, emit message if needed
  processCheck = check:
    let checkPassed = builtins.pathExists check.path;
    in if !checkPassed && check.failureMessage != null then
      formatMessage check.failureMessage
    else if checkPassed && check.successMessage != null then
      ''echo "✓ ${check.successMessage}"''
    else
      "";

  # Filter out empty strings and join
  checkScripts = lib.filter (s: s != "") (map processCheck checks);

in lib.concatStringsSep "\n" checkScripts
