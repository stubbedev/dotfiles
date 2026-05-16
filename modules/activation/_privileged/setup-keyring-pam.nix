_: {
  enableIf = { config, ... }: config.features.hyprland || config.features.niri || config.features.theming;
  args = _: {
    promptTitle = "GNOME Keyring PAM setup";
    promptBody = ''
      This will add GNOME Keyring PAM lines to login session files
      to enable automatic keyring unlock on login.
    '';
    promptQuestion = "Add GNOME Keyring PAM lines?";
    # Lock re-evaluates when any of these appear/disappear so installing
    # a new display manager later forces a re-run.
    stateInputs = [
      "/etc/pam.d/login"
      "/etc/pam.d/ly"
      "/etc/pam.d/lightdm"
      "/etc/pam.d/gdm"
      "/etc/pam.d/sddm"
    ];
    actionScript = ''
      authLine="auth optional pam_gnome_keyring.so"
      sessionLine="session optional pam_gnome_keyring.so auto_start"
      # The password line keeps the `login` keyring's password in sync with
      # the login password when it changes; without it autounlock silently
      # breaks after the next password change (PAM then feeds the new login
      # password to a keyring still sealed with the old one). NixOS's
      # enableGnomeKeyring emits all three lines — match that here so both
      # targets configure PAM identically. `use_authtok` reuses the new
      # password pam_unix already collected earlier in the password stack.
      passwordLine="password optional pam_gnome_keyring.so use_authtok"
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
        grep -qF "$passwordLine" "$file" || printf '%s\n' "$passwordLine" | sudo tee -a "$file" > /dev/null
      done
    '';
  };
}
