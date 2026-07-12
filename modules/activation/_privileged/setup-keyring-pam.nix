_: {
  enableIf =
    { config, ... }: config.features.hyprland || config.features.niri || config.features.theming;
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
        /etc/pam.d/sddm
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

      # Ubuntu's stock /etc/pam.d/sddm puts `auth sufficient pam_unix.so` and
      # `auth sufficient pam_fprintd.so` BEFORE `@include common-auth`. The
      # `sufficient` short-circuit means pam_unix collects the password and
      # exits the auth stack with success — the `-auth optional
      # pam_gnome_keyring.so` line further down never runs, so pam_gnome_keyring
      # at session phase has no password and logs
      # "gkr-pam: no password is available for user". Comment those two lines
      # out so the stack falls through to common-auth (which uses
      # `[success=1 default=ignore]` for pam_unix — non-short-circuit) and the
      # keyring auth line gets PAM_AUTHTOK. Idempotent: the regex only matches
      # uncommented lines.
      if [ -f /etc/pam.d/sddm ]; then
        sudo sed -i -E \
          's|^(auth[[:space:]]+sufficient[[:space:]]+pam_unix\.so.*)|# \1|; s|^(auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so.*)|# \1|' \
          /etc/pam.d/sddm
      fi
    '';
  };
}
