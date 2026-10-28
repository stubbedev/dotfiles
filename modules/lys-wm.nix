{ inputs, ... }:
let
  greetdSessionScript = ''
    [ -n "''${USER:-}" ] || USER="$(id -un)"
    [ -n "''${HOME:-}" ] || HOME="$(getent passwd "$USER" | cut -d: -f6)"
    export USER HOME

    for prof in "$HOME/.nix-profile" "/etc/profiles/per-user/$USER"; do
      if [ -r "$prof/etc/profile.d/hm-session-vars.sh" ]; then
        # shellcheck disable=SC1091
        . "$prof/etc/profile.d/hm-session-vars.sh"
      fi
      case ":$PATH:" in
        *":$prof/bin:"*) ;;
        *) PATH="$prof/bin:$PATH" ;;
      esac
    done
    export PATH

    exec systemd-cat -t lys-wm lys-wm --systemd
  '';
in
{
  flake.modules.nixos.lysWm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      launcher = pkgs.stubbe.shellScript "lys-wm-greetd-session" greetdSessionScript;
    in
    {
      imports = [ inputs.lys-wm.nixosModules.default ];

      config = lib.mkIf config.stubbe.userFeatures.lysWm {
        programs.lys-wm = {
          enable = true;
          package = pkgs.lys-wm;
        };

        services.greetd = {
          enable = true;
          settings = {
            initial_session = {
              command = "${launcher}";
              user = config.host.primaryUser;
            };
            default_session.command = "${lib.getExe' config.services.greetd.package "agreety"} --cmd ${launcher}";
          };
        };
      };
    };

  flake.modules.homeManager.lysWm =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;

      scriptDir = "${config.stubbe.paths.dotfiles}/src/lys-wm/scripts";

      wireplumberHotplug = pkgs.stubbe.bashApp {
        name = "wireplumber-hotplug";
        runtimeInputs = with pkgs; [
          coreutils
          systemd
        ];
        text = builtins.readFile ../src/lys-wm/scripts/wireplumber.hotplug.sh;
      };

      lysWm = gfx.bundle {
        pkg = pkgs.lys-wm;
        exes = [ "lys-wm" ];
      };

      bind = chord: action: { inherit chord action; };
      exec = command: "exec ${command}";
      launch = command: exec "app2unit -- ${command}";
      locked = chord: action: bind chord action // { flags = [ "locked" ]; };

      arrows = {
        Left = "left";
        Right = "right";
        Up = "up";
        Down = "down";
      };
      resizeStep = step: {
        Left = "-${toString step} 0";
        Right = "${toString step} 0";
        Up = "0 -${toString step}";
        Down = "0 ${toString step}";
      };

      workspaceBinds = lib.concatMap (
        i:
        let
          key = toString (lib.mod i 10);
        in
        [
          (bind "SUPER + ${key}" "workspace ${toString i}")
          (bind "SUPER + SHIFT + ${key}" "movetoworkspace ${toString i}")
        ]
      ) (lib.range 1 10);

      arrowBinds = lib.concatLists (
        lib.mapAttrsToList (key: dir: [
          (bind "SUPER + ${key}" "focus ${dir}")
          (bind "SUPER + SHIFT + ${key}" "move ${dir}")
          (bind "SUPER + CTRL + ${key}" "resizeactive ${(resizeStep 50).${key}}")
        ]) arrows
      );

      mediaBinds = lib.mapAttrsToList (key: command: locked key (exec command)) {
        XF86AudioPlay = "playerctl play-pause";
        XF86AudioStop = "playerctl stop";
        XF86AudioPrev = "playerctl previous";
        XF86AudioNext = "playerctl next";
        XF86AudioRaiseVolume = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        XF86AudioLowerVolume = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        XF86AudioMute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        XF86AudioMicMute = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
        XF86MonBrightnessUp = "lys-shell brightness +10";
        XF86MonBrightnessDown = "lys-shell brightness -10";
      };

      resizeSubmap = "resize_mode";

      settings = {
        env = {
          XDG_SESSION_DESKTOP = "lys-wm";
          GDK_BACKEND = "wayland";
          GTK_USE_PORTAL = "0";
          QT_QPA_PLATFORMTHEME = "qt5ct";
          QT_STYLE_OVERRIDE = "kvantum";
          COLOR_SCHEME = "prefer-dark";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          MOZ_ENABLE_WAYLAND = "1";
          TERMINAL = "alacritty";
          XCURSOR_THEME = pkgs.stubbe.theme.cursor;
          XCURSOR_SIZE = toString pkgs.stubbe.theme.cursorSize;
        }
        // lib.optionalAttrs config.host.graphicsNvidia {
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          LIBVA_DRIVER_NAME = "nvidia";
          MOZ_DISABLE_RDD_SANDBOX = "1";
          NVD_BACKEND = "direct";
        };

        outputs = [
          {
            match = "eDP-1";
            scale = 1.5;
          }
          {
            match = "desc:LG Electronics LG HDR WQHD 207NTXRAJ498";
            scale = 1;
          }
          {
            match = "desc:LG Electronics LG HDR 4K 0x00016261";
            scale = 1.5;
          }
          {
            match = "*";
            mode = "highres";
          }
        ];

        input = {
          keyboard = {
            layout = "us,dk,es";
            options = "grp:toggle";
            repeat_rate = 50;
            repeat_delay = 300;
          };
          pointer.accel_profile = "flat";
          touchpad = {
            accel_profile = "flat";
            tap = true;
            drag_lock = true;
            natural_scroll = false;
            disable_while_typing = false;
            middle_emulation = true;
            click_method = "clickfinger";
            scroll_method = "two_finger";
            scroll_factor = 1;
          };
        };

        palette = pkgs.stubbe.withHash;

        tabs = {
          active = {
            background = "mauve";
            text = "text";
          };
          inactive = {
            background = "surface0";
            text = "subtext0";
          };
          urgent = {
            background = "red";
            text = "text";
          };
        };

        binds = [
          (bind "SUPER + Return" (launch "alacritty"))
          (bind "SUPER + SHIFT + E" (launch "pcmanfm"))
          (bind "SUPER + space" (
            exec "rofi -drun-reload-desktop-cache -drun-use-desktop-cache -show drun -location 0 -width 60"
          ))
          (bind "SUPER + SHIFT + space" (
            exec ''rofi -show combi -combi-modes "run" -modes combi -run-command "${scriptDir}/rofi.run.sh {cmd}" -location 0 -width 60''
          ))
          (bind "SUPER + CTRL + space" (exec ''rofi -show combi -combi-modes "window" -modes combi''))
          (bind "SHIFT + Print" (exec "lys-shell screenshot output"))
          (bind "Print" (exec "lys-shell screenshot region"))
          (bind "SUPER + Print" (exec "lys-shell screenshot window"))
          (bind "SUPER + SHIFT + R" (exec "lys-shell recorder toggle"))
          (bind "SUPER + V" (
            exec ''cliphist list | rofi -dmenu | cliphist decode | wl-copy && wtype -M ctrl v -m ctrl && notify-send "Pasted selection"''
          ))
          (bind "SUPER + C" (exec ''wl-copy "$(wl-paste -p)" && notify-send "Copied selection"''))
          (bind "SUPER + M" (launch "mail-open"))
          (bind "SUPER + SHIFT + Q" "kill")
          (bind "SUPER + F" "fullscreen")
          (bind "SUPER + T" "togglefloating")
          (bind "SUPER + Escape" (exec "lys-lock"))
          (bind "SUPER + mouse:272" "movewindow")
          (bind "SUPER + mouse:273" "resizewindow")
          (bind "SUPER + Delete" "exit")
          (bind "SUPER + mouse_down" "focus right")
          (bind "SUPER + bracketright" "focus right")
          (bind "SUPER + mouse_up" "focus left")
          (bind "SUPER + bracketleft" "focus left")
          (bind "SUPER + SHIFT + mouse_down" "workspace e+1")
          (bind "SUPER + SHIFT + bracketright" "workspace e+1")
          (bind "SUPER + Tab" "workspace e+1")
          (bind "SUPER + SHIFT + mouse_up" "workspace e-1")
          (bind "SUPER + SHIFT + bracketleft" "workspace e-1")
          (bind "SUPER + SHIFT + Tab" "workspace e-1")
          (bind "SUPER + R" "submap ${resizeSubmap}")
        ]
        ++ arrowBinds
        ++ workspaceBinds
        ++ mediaBinds;

        submaps.${resizeSubmap} =
          lib.mapAttrsToList (key: step: bind key "resizeactive ${step}" // { flags = [ "repeating" ]; }) (
            resizeStep 10
          )
          ++ [
            (bind "Return" "submap reset")
            (bind "Escape" "submap reset")
          ];

        rules = [
          {
            app_id = "^steam$";
            float = true;
          }
          {
            app_id = "^steam$";
            title = "^Steam$";
            tile = true;
          }
          {
            app_id = "^steam$";
            title = "^Friends List$";
            tile = true;
            size = "400x900";
          }
        ];

        autostart = [
          "wl-paste --watch cliphist store"
          "wl-clip-persist --clipboard regular"
        ];
      };

      sessionTarget = [ config.wayland.systemd.target ];
    in
    {
      imports = [ inputs.lys-wm.homeManagerModules.default ];

      config = lib.mkIf config.features.lysWm {
        programs.lys-wm = {
          enable = true;
          package = lysWm;
        };

        home.packages = with pkgs; [
          app2unit
          wl-clipboard
          wl-clip-persist
          wtype
          libnotify
        ];

        xdg.configFile."lys-wm/config.yaml".source = pkgs.stubbe.gen.yaml "lys-wm-config.yaml" settings;

        wayland.systemd.target = "lys-wm-session.target";

        services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "lys-lock";
              # Lock before logind suspends (hypridle holds a sleep
              # delay-inhibitor), so wake lands on the lock screen instead of
              # flashing the session.
              before_sleep_cmd = "loginctl lock-session";
              # s2idle resume can leave DPMS off; force displays back on.
              after_sleep_cmd = "lys-wmctl dispatch dpms on";
            };
            listener = [
              {
                timeout = 300;
                on-timeout = "loginctl lock-session";
              }
              # Screens off shortly after the lock lands — a locked but lit panel
              # is pure battery drain. on-resume covers wiggle-the-mouse wakeups.
              {
                timeout = 330;
                on-timeout = "lys-wmctl dispatch dpms off";
                on-resume = "lys-wmctl dispatch dpms on";
              }
              # macOS-style idle sleep, battery only. On AC (docked included) the
              # machine stays up so SSH and long builds survive.
              {
                timeout = 900;
                on-timeout = "sh -c 'grep -qx 1 /sys/class/power_supply/AC/online || systemctl suspend'";
              }
            ];
          };
        };

        systemd.user.services = {
          wireplumber-hotplug = {
            Unit = {
              Description = "Restart WirePlumber when a display is plugged in, for its HDMI and DisplayPort audio";
              After = sessionTarget;
              PartOf = sessionTarget;
            };
            Install.WantedBy = sessionTarget;
            Service = {
              Type = "simple";
              ExecStart = lib.getExe wireplumberHotplug;
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };

          hypridle = {
            Unit.Description = lib.mkForce "Hypridle idle daemon (lock, dpms, idle sleep)";
            Service = {
              Environment = [ "PATH=${config.stubbe.paths.nixBin}:/usr/bin:/bin" ];
              Restart = lib.mkForce "on-failure";
              RestartSec = lib.mkForce "2s";
            };
          };
        };

        stubbe.setup = {
          lysWmReload.script = lib.getExe (
            pkgs.stubbe.bashApp {
              name = "lys-wm-reload";
              text = ''
                shopt -s nullglob
                for sock in "/run/user/$(id -u)/lys-wm/"*.sock; do
                  if ! ${lib.getExe' pkgs.lys-wm "lys-wmctl"} --socket "$sock" reload; then
                    echo "lys-wm-reload: lys-wm at $sock kept its running config" >&2
                  fi
                done
              '';
            }
          );

          greetd = {
            privileged = true;
            title = "Installing greetd (autologin login manager, replaces SDDM)";
            body = ''
              Install greetd (which ships the agreety fallback greeter) via the
              host package manager, drop the shared lys-wm session launcher into
              /etc/greetd, write /etc/greetd/config.toml (autologin into lys-wm,
              agreety on logout), and make greetd the system display manager in
              place of SDDM.

              The display-manager swap disables any enabled DM (sddm/gdm/lightdm/…),
              repoints /etc/systemd/system/display-manager.service at
              greetd.service, and sets graphical.target as default. It does NOT
              restart the display manager — it takes effect on next reboot, so the
              current session survives.

              Recovery if autologin ever fails to render: switch to a text console
              (Ctrl+Alt+F3) and log in there to fix or roll back.
            '';
            # Purging another DM's package (deb-systemd-helper purge) deletes the
            # shared display-manager.service alias it once owned, silently
            # disabling greetd; re-run when the alias disappears.
            stateInputs = [ "/etc/systemd/system/display-manager.service" ];
            script =
              let
                launcher = "/etc/greetd/lys-wm-session.sh";
              in
              ''
                ${pkgs.stubbe.setup.hostPackage {
                  detect = "greetd";
                  apt = [ "greetd" ];
                  dnf = [ "greetd" ];
                  pacman = [ "greetd" ];
                }}

                if ! getent passwd greeter >/dev/null 2>&1; then
                  sudo useradd --system --create-home --home-dir /var/lib/greetd \
                    --shell /usr/sbin/nologin --user-group \
                    --groups video,input greeter 2>/dev/null || true
                fi

                ${pkgs.stubbe.setup.text {
                  name = "lys-wm-session.sh";
                  target = launcher;
                  mode = "0755";
                  text = "#!/bin/sh\n" + greetdSessionScript;
                }}

                ${pkgs.stubbe.setup.text {
                  name = "greetd-config.toml";
                  target = "/etc/greetd/config.toml";
                  text = ''
                    [terminal]
                    vt = 7

                    [initial_session]
                    command = "${launcher}"
                    user = "${config.home.username}"

                    [default_session]
                    command = "agreety --cmd ${launcher}"
                    user = "greeter"
                  '';
                }}

                ${pkgs.stubbe.setup.text {
                  name = "greetd-plymouth-order.conf";
                  target = "/etc/systemd/system/greetd.service.d/plymouth-order.conf";
                  text = ''
                    [Unit]
                    After=plymouth-quit.service plymouth-quit-wait.service
                  '';
                }}
                ${pkgs.stubbe.setup.reloadUnits}

                current_dm=""
                if [ -L /etc/systemd/system/display-manager.service ]; then
                  current_dm=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
                fi

                if [ "$current_dm" = "greetd" ]; then
                  echo "greetd is already the default display manager; config refreshed." >&2
                else
                  for dm in sddm gdm gdm3 lightdm lxdm xdm; do
                    if systemctl cat "$dm.service" >/dev/null 2>&1 \
                       && systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
                      echo "Disabling existing display manager: $dm" >&2
                      sudo systemctl disable "$dm.service" >/dev/null 2>&1 || true
                    fi
                  done

                  if [ -L /etc/systemd/system/display-manager.service ]; then
                    tgt=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
                    if [ "$tgt" != "greetd" ]; then
                      sudo rm -f /etc/systemd/system/display-manager.service
                    fi
                  fi

                  sudo systemctl enable greetd.service

                  if [ ! -L /etc/systemd/system/display-manager.service ] \
                     || [ "$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)" != "greetd" ]; then
                    greetd_unit=$(systemctl show -p FragmentPath greetd.service --value 2>/dev/null)
                    if [ -n "$greetd_unit" ] && [ -e "$greetd_unit" ]; then
                      echo "Materialising display-manager.service → $greetd_unit." >&2
                      sudo rm -f /etc/systemd/system/display-manager.service
                      sudo ln -sf "$greetd_unit" /etc/systemd/system/display-manager.service
                    else
                      echo "ERROR: greetd.service has no readable FragmentPath. Display manager alias not set." >&2
                      exit 1
                    fi
                  fi

                  if command -v apt-get >/dev/null 2>&1 && [ -d /etc/X11 ]; then
                    greetd_bin=$(command -v greetd 2>/dev/null || echo /usr/bin/greetd)
                    echo "$greetd_bin" | sudo tee /etc/X11/default-display-manager >/dev/null
                  fi

                  if [ "$(sudo systemctl get-default 2>/dev/null)" != "graphical.target" ]; then
                    sudo systemctl set-default graphical.target >/dev/null
                  fi

                  echo "" >&2
                  echo "greetd is now the default display manager (effective on next reboot)." >&2
                  echo "Not restarting the display manager, to avoid killing the current session." >&2
                fi
              '';
          };
        };
      };
    };
}
