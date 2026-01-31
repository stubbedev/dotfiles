_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationSetupHyprKeyringPam";
  activationName = "setupHyprKeyringPam";
  after = order.after.setupHyprKeyringPam;
  enableIf = { config, ... }: config.features.hyprland;
  provideSudo = true;
  script = _: ''
    set -e

    authLine="auth optional pam_gnome_keyring.so"
    sessionLine="session optional pam_gnome_keyring.so auto_start"
    pamFiles=(
      /etc/pam.d/login
      /etc/pam.d/ly
      /etc/pam.d/lightdm
      /etc/pam.d/gdm
      /etc/pam.d/sddm
    )

    missingFiles=()
    for file in "''${pamFiles[@]}"; do
      if [ ! -f "$file" ]; then
        continue
      fi

      missing=0
      grep -qF "$authLine" "$file" || missing=1
      grep -qF "$sessionLine" "$file" || missing=1

      if [ "$missing" -eq 1 ]; then
        missingFiles+=("$file")
      fi
    done

    if [ "''${#missingFiles[@]}" -eq 0 ]; then
      # Nothing to do, all files already have keyring lines
      true  # Don't exit, just continue (exit would exit entire activation!)
    else
      echo ""
      echo "Missing GNOME Keyring PAM lines in:"
      for file in "''${missingFiles[@]}"; do
        echo "  - $file"
      done
      echo ""
      read -p "Add GNOME Keyring PAM lines to these files? [Y/n] " -n 1 -r
      echo

      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        for file in "''${missingFiles[@]}"; do
          grep -qF "$authLine" "$file" || printf '%s\n' "$authLine" | sudo tee -a "$file" > /dev/null
          grep -qF "$sessionLine" "$file" || printf '%s\n' "$sessionLine" | sudo tee -a "$file" > /dev/null
        done
        echo ""
        echo "✓ GNOME Keyring PAM lines added."
      else
        echo ""
        echo "Skipped GNOME Keyring PAM updates."
      fi
      echo ""
    fi
  '';
}
