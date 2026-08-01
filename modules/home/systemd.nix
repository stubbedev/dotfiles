_: {
  linuxOnlyHomeModules.systemd =
    {
      pkgs,
      lib,
      config,
      scripts,
      homeLib,
      ...
    }:
    let
      hyprlandEnabled = config.features.hyprland;
      anyCompositor = hyprlandEnabled;

      # wayle is the desktop shell (bar + notifications + OSD + wallpaper).
      wayleEnabled = config.features.wayle;

      # Target the compositor activates. Services that should run under the
      # compositor pull from this list for After/PartOf/WantedBy.
      compositorTargets = lib.optional hyprlandEnabled "hyprland-session.target";

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
      systemd.user.targets = lib.optionalAttrs hyprlandEnabled {
        hyprland-session.Unit.Description = "Hyprland session";
      };

      # Blue-light scheduling is now wayle's native hyprsunset module (it owns
      # the daemon + solar schedule), and the xdg-desktop-portal backend is wayle
      # too (modules/nixos/wayle.nix on NixOS, modules/home/wayle-portal.nix on
      # standalone HM) — so the old hyprland-only portal + hyprsunset-sun services
      # are both gone.
      systemd.user.services =
        # wayle shell — bar + notifications + OSD + wallpaper in one daemon.
        (lib.optionalAttrs wayleEnabled {
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
          # src/hypr/hyprland.lua) finds no
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

          # Single-instance alacritty: one daemon process all terminals attach
          # to via `alacritty msg create-window` (the `alacritty` client wrapper
          # in modules/packages/system.nix). Starts only after the compositor
          # target — so the imported Wayland env is present when windows are
          # created — which also removes the spawn/poll race the old standalone
          # wrapper needed. --socket pins a deterministic path the client mirrors
          # (%t = $XDG_RUNTIME_DIR).
          alacritty-daemon = {
            Unit = {
              Description = "Alacritty daemon (shared single-instance process)";
              After = compositorTargets;
              PartOf = compositorTargets;
            };
            Install.WantedBy = compositorTargets;
            Service = {
              Type = "simple";
              ExecStart = "${homeLib.gfx pkgs.alacritty}/bin/alacritty --socket %t/alacritty.sock --daemon";
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
