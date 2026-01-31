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
      systemd.user.services = {
        xdg-desktop-portal-hyprland = {
          Unit = {
            Description = "Portal service (Hyprland implementation)";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
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
              "graphical-session.target"
              "power-profiles-daemon.service"
              "xdg-desktop-portal-hyprland.service"
            ];
            Wants = [ "power-profiles-daemon.service" ];
            PartOf = [ "graphical-session.target" ];
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${constants.paths.hypr}/scripts/waybar.launch.sh";
            ExecStopPost = "-${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -9 waybar || true; sleep 0.5'";
            Restart = "on-failure";
            RestartSec = "3s";
          };
        };
      };
    };
}
