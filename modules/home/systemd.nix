_: {
  linuxOnlyHomeModules.systemd =
    {
      constants,
      pkgs,
      lib,
      config,
      scripts,
      ...
    }:
    let
      hyprlandEnabled = config.features.hyprland;
      niriEnabled = config.features.niri;
      anyCompositor = hyprlandEnabled || niriEnabled;

      # wayle replaces waybar + swaync + hyprpaper in one shell. While the
      # flag is off the legacy stack runs; flipping it on swaps atomically.
      wayleEnabled = config.features.wayle;
      legacyShell = !wayleEnabled;

      # The bar that the await-* hooks bounce when a late-starting service
      # (power-profiles-daemon, bluetooth) appears — whichever shell is live.
      barService = if wayleEnabled then "wayle.service" else "waybar.service";

      # Targets the active compositor activates. Services that should run
      # under either compositor pull from this list for After/PartOf/WantedBy.
      compositorTargets =
        (lib.optional hyprlandEnabled "hyprland-session.target")
        ++ (lib.optional niriEnabled "niri-session.target");

      compositorActiveCondition = lib.concatMapStringsSep " || " (
        target: "${pkgs.systemd}/bin/systemctl --user is-active --quiet ${target}"
      ) compositorTargets;

      restartBarIfCompositorActive = pkgs.writeShellScript "restart-bar-if-compositor-active" ''
        if ${compositorActiveCondition}; then
          exec ${pkgs.systemd}/bin/systemctl --user restart ${barService}
        fi
      '';

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
        # Hyprland-only service: portal.
        lib.optionalAttrs hyprlandEnabled {
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

        }
        // (lib.optionalAttrs (hyprlandEnabled && legacyShell) {
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
        # Legacy shell (waybar + swaync) — runs only while features.wayle is off.
        // (lib.optionalAttrs legacyShell {
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
              # Make sd-switch restart waybar when its config changes too,
              # not only when the unit definition itself changes. The store
              # path under config.xdg.configFile.waybar.source moves whenever
              # anything under src/waybar/ is touched — embedding it here
              # bumps the unit hash and triggers a single restart that
              # subsumes what the old onChange hook did.
              X-Restart-Triggers = [ (toString config.xdg.configFile."waybar".source) ];
            };
            Install.WantedBy = compositorTargets;
            Service = {
              Type = "simple";
              ExecStart = "${scripts.waybar-launch}/bin/waybar-launch";
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
        })
        # wayle shell — bar + notifications + OSD + wallpaper in one daemon.
        // (lib.optionalAttrs wayleEnabled {
          wayle = {
            Unit = {
              Description = "Wayle desktop shell (bar, notifications, OSD, wallpaper)";
              Documentation = "https://github.com/wayle-rs/wayle";
              After = compositorTargets ++ [ "power-profiles-daemon.service" ];
              Wants = [ "power-profiles-daemon.service" ];
              PartOf = compositorTargets;
              # Same rationale as waybar: bump the unit hash when the config
              # store path moves so sd-switch restarts wayle on config edits.
              X-Restart-Triggers = [ (toString config.xdg.configFile."wayle".source) ];
            };
            Install.WantedBy = compositorTargets;
            Service = {
              # Type=simple, not dbus: wayle is a full shell (like the bar),
              # not solely a notification daemon. Its notification service
              # (org.freedesktop.Notifications, replacing swaync) is claimed
              # during shell startup. Type=dbus+BusName would make systemd
              # block on that name and time out the whole unit if it is
              # claimed late or notifications are disabled — simple avoids that.
              Type = "simple";
              ExecStart = "${scripts.wayle-launch}/bin/wayle-launch";
              ExecStopPost = "-${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -9 wayle || true; sleep 0.5'";
              Restart = "on-failure";
              RestartSec = "3s";
            };
          };
        })
        // {
          # hyprpolkitagent ships only $out/libexec/hyprpolkitagent — no bin
          # entry — so home-manager's bin-only linking can't surface it and
          # `systemctl --user start hyprpolkitagent` (called from
          # src/hypr/hyprland.lua and conceptually from niri) finds no
          # unit. Defining the service here fixes both compositors and
          # gives pkexec something to talk to when our 49-openconnect.rules
          # rule doesn't match (e.g. nmcli, brightness, anything that
          # escalates outside the VPN scripts).
          hyprpolkitagent = {
            Unit = {
              Description = "Hyprland polkit authentication agent";
              After = compositorTargets;
              PartOf = compositorTargets;
            };
            Install.WantedBy = compositorTargets;
            Service = {
              Type = "simple";
              ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
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
              ExecStart = "${restartBarIfCompositorActive}";
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
              ExecStart = "${restartBarIfCompositorActive}";
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
              # Bound the restart loop. Without this a misconfigured polkit
              # rule (or any persistent failure) spins forever, silently
              # burning the dbus-monitor handshake every 5s with no visible
              # signal in `systemctl status`. With these set the unit goes
              # into `failed` state after 5 retries / 60s — `journalctl -u`
              # and waybar's failed-units widget surface it loudly.
              StartLimitBurst = 5;
              StartLimitIntervalSec = 60;
            };
            Install.WantedBy = [ "default.target" ];
            Service = {
              Type = "simple";
              ExecStart = "${scripts.power-profile-fix}/bin/power-profile-fix";
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
