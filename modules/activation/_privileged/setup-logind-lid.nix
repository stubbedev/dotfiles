_: {
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "systemd-logind lid switch handler";
      body = ''
        This installs a drop-in that makes systemd-logind ignore the lid
        switch, so closing the lid does not suspend the machine. The
        laptop stays reachable over SSH with the lid closed.
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/systemd/logind.conf.d

        ${homeLib.installSystemFile {
          target = "/etc/systemd/logind.conf.d/10-lid-ignore.conf";
          content = ''
            # managed-by: home-manager logind-lid
            [Login]
            HandleLidSwitch=ignore
            HandleLidSwitchExternalPower=ignore
          '';
        }}

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl kill -s HUP systemd-logind.service >/dev/null 2>&1 || true
        fi
      '';
    };
}
