_: {
  moduleName = "activationSetupHyprlockPam";
  activationName = "setupHyprlockPam";
  enableIf = { config, ... }: config.features.hyprland;
  args = _: {
    promptTitle = "⚠️  Hyprlock PAM configuration missing";
    promptBody = ''
      Hyprlock needs a PAM configuration to authenticate passwords.
      This will create a minimal Nix-compatible PAM config.
    '';
    promptQuestion = "Create /etc/pam.d/hyprlock?";
    actionScript = ''
      sudo tee /etc/pam.d/hyprlock > /dev/null << 'EOF'
      #%PAM-1.0
      auth       sufficient   pam_unix.so nullok
      auth       required     pam_deny.so

      account    required     pam_unix.so

      password   required     pam_unix.so nullok

      session    required     pam_unix.so
      EOF
    '';
    skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
  };
}
