_: {
  enableIf = { config, ... }: config.features.hyprland || config.features.theming;
  args = _: {
    promptTitle = "GNOME Keyring PAM setup";
    promptBody = ''
      This will add GNOME Keyring PAM lines to login session files
      to enable automatic keyring unlock on login.
    '';
    # Lock re-evaluates when any of these appear/disappear so installing
    # a new display manager later forces a re-run.
    stateInputs = [
      "/etc/pam.d/login"
      "/etc/pam.d/ly"
      "/etc/pam.d/lightdm"
      "/etc/pam.d/gdm"
      "/etc/pam.d/greetd"
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
      # Idempotency check uses a tolerant regex: distro-shipped stack lines
      # like `-auth   optional        pam_gnome_keyring.so` (dash prefix,
      # tabs, multi-space) used to escape a literal-string match and we
      # appended a duplicate on every activation. Now we match any
      # non-comment line in the right phase that references
      # pam_gnome_keyring.so.
      pamFiles=(
        /etc/pam.d/login
        /etc/pam.d/ly
        /etc/pam.d/lightdm
        /etc/pam.d/gdm
        /etc/pam.d/greetd
      )
      hasPhase() {
        local file="$1" phase="$2"
        grep -qE "^[[:space:]]*-?''${phase}[[:space:]]+\S+[[:space:]]+.*pam_gnome_keyring\.so" "$file"
      }
      for file in "''${pamFiles[@]}"; do
        [ -f "$file" ] || continue
        hasPhase "$file" auth     || printf '%s\n' "$authLine"     | sudo tee -a "$file" > /dev/null
        hasPhase "$file" session  || printf '%s\n' "$sessionLine"  | sudo tee -a "$file" > /dev/null
        hasPhase "$file" password || printf '%s\n' "$passwordLine" | sudo tee -a "$file" > /dev/null
      done
    '';
  };
}
