{ config, pkgs, lib, homeLib, ... }:

let
  pamPath = "/etc/pam.d/hyprlock";

  pamContent = ''
    #%PAM-1.0
    # Minimal PAM config for hyprlock using only Nix PAM modules
    auth       sufficient   pam_unix.so nullok
    auth       required     pam_deny.so

    account    required     pam_unix.so

    password   required     pam_unix.so nullok

    session    required     pam_unix.so
  '';

  setupScript = homeLib.sudoPromptScript {
    inherit pkgs;
    name = "setup-hyprlock-pam";
    preCheck = ''
      if [ -f "${pamPath}" ]; then
        exit 0
      fi
    '';
    promptTitle = "⚠️  Hyprlock PAM configuration missing";
    promptBody = ''
      echo "Hyprlock needs a PAM configuration to authenticate passwords."
      echo "This will create a minimal Nix-compatible PAM config."
    '';
    promptQuestion = "Create ${pamPath}?";
    actionScript = ''
      echo "${pamContent}" | $SUDO tee "${pamPath}" > /dev/null
      echo ""
      echo "✓ PAM configuration created successfully!"
    '';
    skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
  };

in ''
  ${setupScript}
''
