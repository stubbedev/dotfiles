_: {
  moduleName = "activationSetupHyprKeyringPam";
  activationName = "setupHyprKeyringPam";
  enableIf = { config, ... }: config.features.hyprland;
  args = _: {
    promptTitle = "GNOME Keyring PAM setup";
    promptBody = ''
      This will add GNOME Keyring PAM lines to login session files
      to enable automatic keyring unlock on login.
    '';
    promptQuestion = "Add GNOME Keyring PAM lines?";
    actionScript = ''
      authLine="auth optional pam_gnome_keyring.so"
      sessionLine="session optional pam_gnome_keyring.so auto_start"
      pamFiles=(
        /etc/pam.d/login
        /etc/pam.d/ly
        /etc/pam.d/lightdm
        /etc/pam.d/gdm
        /etc/pam.d/sddm
      )
      for file in "''${pamFiles[@]}"; do
        [ -f "$file" ] || continue
        grep -qF "$authLine" "$file" || printf '%s\n' "$authLine" | sudo tee -a "$file" > /dev/null
        grep -qF "$sessionLine" "$file" || printf '%s\n' "$sessionLine" | sudo tee -a "$file" > /dev/null
      done
    '';
    skipMessage = "Skipped. You can add them later by running: home-manager switch --flake . --impure";
  };
}
