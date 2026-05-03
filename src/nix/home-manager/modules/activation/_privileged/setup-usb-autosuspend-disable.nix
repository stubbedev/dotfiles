_:
let
  usbAudioPowerRules = builtins.readFile ../../../../../udev/rules.d/90-usb-audio-power.rules;
in
{
  enableIf = { config, ... }: config.features.desktop;
  args = _: {
    promptTitle = "Installing USB power management rules";
    promptBody = ''
      This keeps USB devices in full-power mode and disables autosuspend
      for USB audio devices to avoid missed first keypresses and audio pops.
    '';
    promptQuestion = "Install USB power management rules?";
    actionScript = ''
      rulesDir=/etc/udev/rules.d
      autosuspendRuleFile="$rulesDir/90-usb-autosuspend-disable.rules"
      audioRuleFile="$rulesDir/90-usb-audio-power.rules"

      autosuspendTmpfile=$(mktemp)
      audioTmpfile=$(mktemp)
      trap 'rm -f "$autosuspendTmpfile" "$audioTmpfile"' EXIT

      cat > "$autosuspendTmpfile" << 'EOF'
      # managed-by: home-manager usb-autosuspend-disable v1
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"
      EOF

      cat > "$audioTmpfile" << 'EOF'
      ${usbAudioPowerRules}
      EOF

      sudo install -d -m 0755 "$rulesDir"
      sudo install -m 0644 "$autosuspendTmpfile" "$autosuspendRuleFile"
      sudo install -m 0644 "$audioTmpfile" "$audioRuleFile"
      sudo chown root:root "$autosuspendRuleFile" "$audioRuleFile"

      for control in /sys/bus/usb/devices/*/power/control; do
        if [ -w "$control" ]; then
          printf 'on' | sudo tee "$control" >/dev/null
        fi
      done

      # Reload rules so new plug events pick them up. Do NOT re-trigger
      # add events on already-attached devices: that re-enumerates the
      # Thunderbolt dock and can wedge the HDA codec's DP audio MUX
      # (kernel ELD valid, codec ELDV=0, MUX stuck on a phantom Dev).
      # New rules apply automatically on next replug or reboot.
      if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm control --reload-rules >/dev/null 2>&1 || true
      fi
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
