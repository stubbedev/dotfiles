_: {
  linuxOnlyHomeModules.systemd =
    {
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

      # wayle is the desktop shell (bar + notifications + OSD + wallpaper).
      wayleEnabled = config.features.wayle;

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
          exec ${pkgs.systemd}/bin/systemctl --user restart wayle.service
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
              # xdph reads xdph.conf once at startup and caches the screencast
              # custom_picker_binary path (modules/packages/hyprland/portal.nix).
              # That path is now a stable profile path, so it no longer moves on
              # a wayle bump — but should we ever edit the conf itself, the unit
              # definition is otherwise unchanged and sd-switch would leave the
              # old xdph running with stale config. Bump the unit hash when
              # xdph.conf's content changes so sd-switch restarts the portal,
              # same trick as wayle.service below.
              X-Restart-Triggers = [
                (toString config.xdg.configFile."hypr/xdph.conf".source)
              ];
            };
            Service = {
              Type = "dbus";
              BusName = "org.freedesktop.impl.portal.desktop.hyprland";
              ExecStart = "${pkgs.xdg-desktop-portal-hyprland}/libexec/xdg-desktop-portal-hyprland";
              Restart = "on-failure";
            };
          };

          # Blue-light scheduler. hyprsunset has no native lat/long mode, so this
          # owns the schedule: sunwait computes the real sunrise/sunset and it
          # ramps the daemon's temperature over its IPC socket, writing the wayle
          # widget's state on each change (and re-evaluating on SIGUSR1 from the
          # toggle). Restart=always so the schedule survives a crash — a bare
          # autostart exec (like hypridle) wouldn't. It self-waits for the
          # hyprsunset socket, so no hard ordering against the lua autostart.
          hyprsunset-sun = {
            Unit = {
              Description = "hyprsunset sunrise/sunset blue-light scheduler";
              After = [ "hyprland-session.target" ];
              PartOf = [ "hyprland-session.target" ];
            };
            Install.WantedBy = [ "hyprland-session.target" ];
            Service = {
              Type = "simple";
              ExecStart = "${scripts.hyprsunset-sun}/bin/hyprsunset-sun";
              Restart = "always";
              RestartSec = "5s";
            };
          };
        }
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
              X-Restart-Triggers = [ (toString config.xdg.configFile."wayle/config.toml".source) ];
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
          # and only exist to bounce the wayle bar when their dependent service starts.
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
