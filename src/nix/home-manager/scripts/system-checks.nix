{ config, pkgs, lib, ... }:

let
  # Define all system checks here
  # NOTE: Checks that require sudo should be moved to interactive setup scripts
  # (see setup-pam-wrappers.nix, setup-hyprlock-pam.nix, setup-sddm-session.nix)
  checks = [
    # Add future system checks here that are read-only and don't require sudo
  ];

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
