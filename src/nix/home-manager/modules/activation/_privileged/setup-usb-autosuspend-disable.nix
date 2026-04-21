_: {
  enableIf = { config, ... }: config.features.desktop;
  args = _: {
    promptTitle = "Installing USB autosuspend disable rule";
    promptBody = ''
      This keeps USB devices in full-power mode (power/control=on)
      to avoid missed first keypresses after idle.
    '';
    promptQuestion = "Install USB autosuspend disable rule?";
    actionScript = ''
      rulesDir=/etc/udev/rules.d
      ruleFile="$rulesDir/90-usb-autosuspend-disable.rules"

      tmpfile=$(mktemp)
      trap 'rm -f "$tmpfile"' EXIT
      cat > "$tmpfile" << 'EOF'
      # managed-by: home-manager usb-autosuspend-disable v1
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
      EOF

      sudo install -d -m 0755 "$rulesDir"
      sudo install -m 0644 "$tmpfile" "$ruleFile"
      sudo chown root:root "$ruleFile"

      for control in /sys/bus/usb/devices/*/power/control; do
        if [ -w "$control" ]; then
          printf 'on' | sudo tee "$control" >/dev/null
        fi
      done

      if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        sudo udevadm trigger --subsystem-match=usb --action=add >/dev/null 2>&1 || true
      fi
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
