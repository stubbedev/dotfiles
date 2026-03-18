_: {
  flake.modules.homeManager.systemd =
    {
      constants,
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.hyprland {
      systemd.user.targets = {
        hyprland-session = {
          Unit = {
            Description = "Hyprland session";
          };
        };
      };
      systemd.user.services = {
        xdg-desktop-portal-hyprland = {
          Unit = {
            Description = "Portal service (Hyprland implementation)";
            PartOf = [ "hyprland-session.target" ];
            After = [ "hyprland-session.target" ];
          };
          Service = {
            Type = "dbus";
            BusName = "org.freedesktop.impl.portal.desktop.hyprland";
            ExecStart = "${pkgs.xdg-desktop-portal-hyprland}/libexec/xdg-desktop-portal-hyprland";
            Restart = "on-failure";
          };
        };

        await-powerprofile = {
          Unit = {
            Description = "Restart Waybar when power-profiles-daemon starts";
            After = [
              "default.target"
              "power-profiles-daemon.service"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl --user restart waybar.service";
            Restart = "no";
          };
        };
        await-bluetooth = {
          Unit = {
            Description = "Restart Waybar when bluetooth starts";
            After = [
              "default.target"
              "bluetooth.service"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl --user restart waybar.service";
            Restart = "no";
          };
        };

        gnome-keyring-daemon = {
          Unit = {
            Description = "GNOME Keyring daemon (secrets component)";
            PartOf = [ "graphical-session.target" ];
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --foreground --components=secrets";
            Restart = "on-failure";
            RestartSec = "2s";
          };
        };

        await-gnome-keyring = {
          Unit = {
            Description = "Restart Waybar when gnome-keyring is unlocked";
            After = [
              "waybar.service"
              "gnome-keyring-daemon.service"
            ];
            # Only run once per session, not on every waybar restart
            ConditionPathExists = "!/tmp/await-gnome-keyring-done-%U";
          };
          Install = {
            # Start after hyprland session, not tied to waybar
            WantedBy = [ "hyprland-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${constants.paths.hypr}/scripts/await.keyring.unlocked.sh";
            # Mark as done so it doesn't run again this session
            ExecStartPost = "/usr/bin/touch /tmp/await-gnome-keyring-done-%U";
            Restart = "no";
            TimeoutStartSec = "10s";
            RemainAfterExit = true;
          };
        };

        power-profile-fix = {
          Unit = {
            Description = "Fix CPU frequency scaling for power profiles";
            After = [
              "default.target"
              "power-profiles-daemon.service"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${constants.paths.hypr}/scripts/power-profile-fix.sh";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };

        waybar = {
          Unit = {
            Description = "Waybar - Highly customizable Wayland bar";
            Documentation = "https://github.com/Alexays/Waybar/wiki";
            After = [
              "hyprland-session.target"
              "power-profiles-daemon.service"
              "xdg-desktop-portal-hyprland.service"
            ];
            Wants = [ "power-profiles-daemon.service" ];
            PartOf = [ "hyprland-session.target" ];
          };
          Install = {
            WantedBy = [ "hyprland-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${constants.paths.hypr}/scripts/waybar.launch.sh";
            ExecStopPost = "-${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -9 waybar || true; sleep 0.5'";
            Restart = "on-failure";
            RestartSec = "3s";
          };
        };

        swaync = {
          Unit = {
            Description = "SwayNotificationCenter";
            After = [ "hyprland-session.target" ];
            PartOf = [ "hyprland-session.target" ];
          };
          Install = {
            WantedBy = [ "hyprland-session.target" ];
          };
          Service = {
            Type = "dbus";
            BusName = "org.freedesktop.Notifications";
            ExecStart = "${constants.paths.nixBin}/swaync";
            Restart = "on-failure";
            RestartSec = "2s";
          };
        };
      };
    };
}
