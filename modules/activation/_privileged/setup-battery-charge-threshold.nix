{ self, ... }:
{
  enableIf = { config, ... }: config.features.desktop;
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "battery charge threshold (80%)";
      body = ''
        This machine spends most of its life on a dock; holding lithium at
        100% is what ages it fastest. This installs a udev rule that caps
        charging at 80% (resume below 75%) via the ThinkPad EC, and applies
        the thresholds immediately. Costs ~1h of unplugged runtime; buys
        battery capacity measured in years. Charge to full for a trip with
        `echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`
        — the rule restores 80% on next boot.
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/udev/rules.d

        ${homeLib.installSystemFile {
          target = "/etc/udev/rules.d/85-battery-charge-threshold.rules";
          content = builtins.readFile (self + "/src/udev/rules.d/85-battery-charge-threshold.rules");
        }}

        if command -v udevadm >/dev/null 2>&1; then
          sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        fi

        # Apply now — the rule only fires on the next battery "add" (boot).
        # start first: 75 is below any current end, and end=80 is above 75,
        # so the EC accepts both writes in this order from any prior state.
        bat=/sys/class/power_supply/BAT0
        if [ -f "$bat/charge_control_end_threshold" ]; then
          echo 75 | sudo tee "$bat/charge_control_start_threshold" >/dev/null
          echo 80 | sudo tee "$bat/charge_control_end_threshold" >/dev/null
        fi
      '';
    };
}
