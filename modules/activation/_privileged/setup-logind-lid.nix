_: {
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "systemd-logind lid switch handler";
      body = ''
        macOS-style lid behaviour: closing the lid suspends (s2idle) on
        battery and on AC, but the machine stays awake in clamshell mode
        when an external display is connected (logind's "docked" state
        counts connected non-eDP DRM connectors). Opening the lid wakes.

        Undocking with the lid already closed is handled separately by
        src/hypr/scripts/monitor.toggle.sh — logind only acts on the lid
        switch edge, not on later display changes (systemd#7690).
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/systemd/logind.conf.d

        ${homeLib.installSystemFile {
          target = "/etc/systemd/logind.conf.d/10-lid.conf";
          content = ''
            # managed-by: home-manager logind-lid
            [Login]
            HandleLidSwitch=suspend
            HandleLidSwitchExternalPower=suspend
            HandleLidSwitchDocked=ignore
          '';
        }}

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl kill -s HUP systemd-logind.service >/dev/null 2>&1 || true
        fi
      '';
    };
}
