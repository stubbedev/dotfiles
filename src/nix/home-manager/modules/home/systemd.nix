_: {
  flake.modules.homeManager.systemd =
    {
      constants,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      hyprlandEnabled = config.features.hyprland;
      niriEnabled = config.features.niri;
      anyCompositor = hyprlandEnabled || niriEnabled;

      # Targets the active compositor activates. Services that should run
      # under either compositor pull from this list for After/PartOf/WantedBy.
      compositorTargets =
        (lib.optional hyprlandEnabled "hyprland-session.target")
        ++ (lib.optional niriEnabled "niri-session.target");

      secretsExec =
        if builtins.pathExists /usr/bin/ksecretd then
          "/usr/bin/ksecretd"
        else if builtins.pathExists /usr/bin/gnome-keyring-daemon then
          "/usr/bin/gnome-keyring-daemon --start --foreground --components=secrets"
        else if builtins.pathExists /usr/bin/pass-secret-service then
          "/usr/bin/pass-secret-service"
        else
          null;
    in
    lib.mkIf anyCompositor {
      systemd.user.targets =
        (lib.optionalAttrs hyprlandEnabled {
          hyprland-session.Unit.Description = "Hyprland session";
        })
        // (lib.optionalAttrs niriEnabled {
          niri-session.Unit.Description = "niri session";
        });

      systemd.user.services =
        # Hyprland-only services: portal + wallpaper daemon.
        (lib.optionalAttrs hyprlandEnabled {
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

          hyprpaper = {
            Unit = {
              Description = "Hyprpaper wallpaper daemon";
              After = [ "hyprland-session.target" ];
              PartOf = [ "hyprland-session.target" ];
            };
            Install.WantedBy = [ "hyprland-session.target" ];
            Service = {
              Type = "simple";
              ExecStart = "${constants.paths.nixBin}/hyprpaper";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };
        })
        # Shared services: follow whichever compositor target is active.
        // {
          waybar = {
            Unit = {
              Description = "Waybar - Highly customizable Wayland bar";
              Documentation = "https://github.com/Alexays/Waybar/wiki";
              After =
                compositorTargets
                ++ [ "power-profiles-daemon.service" ]
                ++ (lib.optional hyprlandEnabled "xdg-desktop-portal-hyprland.service");
              Wants = [ "power-profiles-daemon.service" ];
              PartOf = compositorTargets;
            };
            Install.WantedBy = compositorTargets;
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
              After = compositorTargets;
              PartOf = compositorTargets;
            };
            Install.WantedBy = compositorTargets;
            Service = {
              Type = "dbus";
              BusName = "org.freedesktop.Notifications";
              ExecStart = "${constants.paths.nixBin}/swaync";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };

          # Independent of compositor target — these run under default.target
          # and only exist to bounce waybar when their dependent service starts.
          await-powerprofile = {
            Unit = {
              Description = "Restart Waybar when power-profiles-daemon starts";
              After = [
                "default.target"
                "power-profiles-daemon.service"
              ];
            };
            Install.WantedBy = [ "default.target" ];
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
            Install.WantedBy = [ "default.target" ];
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
            Install.WantedBy = [ "default.target" ];
            Service = {
              Type = "simple";
              ExecStart = "${constants.paths.hypr}/scripts/power.profile.fix.sh";
              ExecStop = "${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -TERM -f dbus-monitor.*PowerProfiles || true'";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };
        }
        // (lib.optionalAttrs (secretsExec != null) {
          secrets-service = {
            Unit = {
              Description = "D-Bus secrets service (org.freedesktop.secrets)";
              After = compositorTargets;
              PartOf = compositorTargets;
            };
            Install.WantedBy = compositorTargets;
            Service = {
              Type = "dbus";
              BusName = "org.freedesktop.secrets";
              ExecCondition = "/bin/sh -c '! ${pkgs.systemd}/bin/busctl --user status org.freedesktop.secrets 2>/dev/null'";
              ExecStart = secretsExec;
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };
        });
    };
}
