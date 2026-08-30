{ inputs, ... }:
{
  flake.modules.nixos.wayle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Nesting this in lib.mkIf makes the upstream module and its options vanish.
      imports = [ inputs.wayle.nixosModules.default ];

      config =
        let
          enabled = config.stubbe.userFeatures.wayle && config.stubbe.userFeatures.hyprland;
        in
        lib.mkIf enabled {
          programs.wayle = {
            enable = true;
            package = pkgs.wayle;
            systemd.enable = false;
            portal.enable = true;
            lock.enable = true;
          };

          # programs.hyprland registers a per-desktop portal section that beats
          # common.default, so mkForce is needed to drop it.
          xdg.portal.config = lib.mkForce {
            common.default = [
              "wayle"
              "gnome"
              "gtk"
            ];
          };
        };
    };

  flake.modules.homeManager.wayle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      enabled = config.features.wayle && config.features.hyprland;

      # Rejoined with the upstream package so $out/share reaches the profile:
      # without it GTK cannot resolve wayle's bundled icon names.
      waylePackage = gfx.bundle {
        pkg = pkgs.wayle;
        exes = [
          "wayle"
          "wayle-settings"
        ];
      };

      hasBattery =
        let
          psu = /. + "/sys/class/power_supply";
        in
        builtins.pathExists psu
        && lib.any (lib.hasPrefix "BAT") (builtins.attrNames (builtins.readDir psu));

      # The gfx symlinkJoin carries no meta.mainProgram.
      wayleBin = lib.getExe' waylePackage "wayle";

      launcher = pkgs.stubbe.bashApp {
        name = "wayle-launch";
        text = ''
          # Environment probing: the session vars may legitimately be unset and
          # detection loops tolerate failing probes — no strict mode.
          set +e +u +o pipefail

          shopt -s nullglob

          uid=$(id -u)
          runtime="''${XDG_RUNTIME_DIR:-/run/user/$uid}"

          CURRENT_INSTANCE=""
          attempt=0

          if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            if [ -S "/run/user/$uid/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
              CURRENT_INSTANCE="$HYPRLAND_INSTANCE_SIGNATURE"
            fi
          fi

          # Only scan for a Hyprland instance if we look like a Hyprland session;
          # otherwise jump straight to launching wayle.
          if [ -z "$CURRENT_INSTANCE" ] && [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
            while [ $attempt -lt 50 ] && [ -z "$CURRENT_INSTANCE" ]; do
              for lockfile in "/run/user/$uid/hypr/"*/hyprland.lock; do
                instance_dir="''${lockfile%/*}"
                if [ -S "$instance_dir/.socket.sock" ]; then
                  CURRENT_INSTANCE="''${instance_dir##*/}"
                  break
                fi
              done

              if [ -z "$CURRENT_INSTANCE" ]; then
                sleep 0.1
              fi
              attempt=$((attempt + 1))
            done
          fi

          if [ -n "$CURRENT_INSTANCE" ]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
          fi

          # A Wayland socket file alone isn't proof a compositor is alive — when a
          # compositor exits abnormally (or libwayland falls back to wayland-2 because
          # wayland-1 is taken, then exits) the socket file lingers. libwayland's lock
          # file is held with flock by the live compositor, so a non-blocking flock
          # that succeeds means nobody owns the socket.
          _wayland_live() {
            local display="$1"
            [ -S "$runtime/$display" ] || return 1
            [ -e "$runtime/$display.lock" ] || return 1
            ! flock -n -x "$runtime/$display.lock" true 2>/dev/null
          }

          # Auto-detect WAYLAND_DISPLAY if not set or if the socket is stale.
          if [ -n "$WAYLAND_DISPLAY" ] && _wayland_live "$WAYLAND_DISPLAY"; then
            :
          else
            unset WAYLAND_DISPLAY
            attempt=0
            while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
              for socket in "$runtime"/wayland-[0-9]*; do
                # Skip lock/aux files — real sockets are wayland-<digits>, no dot.
                case "$socket" in *.*) continue ;; esac
                candidate="''${socket##*/}"
                if _wayland_live "$candidate"; then
                  export WAYLAND_DISPLAY="$candidate"
                  break
                fi
              done

              if [ -z "$WAYLAND_DISPLAY" ]; then
                sleep 0.1
              fi
              attempt=$((attempt + 1))
            done
          fi

          if [ -z "$WAYLAND_DISPLAY" ] || ! _wayland_live "$WAYLAND_DISPLAY"; then
            echo "No live Wayland compositor found, retrying via systemd" >&2
            exit 1
          fi

          export GDK_BACKEND=wayland

          # Apply the same wallpaper to every monitor. `wayle wallpaper set` without
          # --monitor targets all of them, but needs the shell's IPC up first, so retry
          # in the background (≈10s budget) and don't block the shell launch. Startup-
          # only; the loop exits as soon as the set succeeds. The wallpaper path is
          # stubbe.paths.wallpaper — also exported as the WALLPAPER session variable
          # for the DRM-hotplug listener.
          (
            n=0
            while [ $n -lt 40 ]; do
              if ${wayleBin} wallpaper set "${config.stubbe.paths.wallpaper}" --fit fill >/dev/null 2>&1; then
                break
              fi
              n=$((n + 1))
              sleep 0.25
            done
          ) &

          # Replace this shell with the desktop shell (no lingering wrapper process).
          exec ${wayleBin} shell
        '';
      };

      sessionTarget = [ "hyprland-session.target" ];

      restartBarIfSessionActive = pkgs.writeShellScript "restart-bar-if-session-active" ''
        if ${lib.getExe' pkgs.systemd "systemctl"} --user is-active --quiet ${lib.head sessionTarget}; then
          exec ${lib.getExe' pkgs.systemd "systemctl"} --user restart wayle.service
        fi
      '';

      awaitUnit = description: unit: {
        Unit = {
          Description = description;
          After = [
            "default.target"
            unit
          ];
        };
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "oneshot";
          ExecStart = "${restartBarIfSessionActive}";
          Restart = "no";
        };
      };
    in
    {
      imports = [ inputs.wayle.homeManagerModules.default ];

      config = lib.mkIf enabled {
        programs.wayle = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          package = waylePackage;
          systemd.enable = false;
          # Empty so the module does not also write config.toml.
          settings = { };
          portal.enable = true;
        };

        home.packages = [
          waylePackage
          launcher
          (gfx.wrap pkgs.awww)
          (gfx.wrapExe "awww-daemon" pkgs.awww)
          (gfx.wrap pkgs.wleave)
          (pkgs.stubbe.bashApp {
            name = "wayle-widget";
            text = ''
              # -u and pipefail, but NOT -e: watchers tolerate transient
              # command failures (emit_line guards them itself).
              set +e
              set -uo pipefail

              # Emit one reshaped line for a poll-style status cmd: JSON when it has output,
              # else an empty line (hide-if-empty collapses it). Never exits the watcher.
              emit_line() {
                local filt="$1" out
                shift
                out="$("$@" 2>/dev/null)" || { echo; return; }
                [ -n "$out" ] || { echo; return; }
                printf '%s\n' "$(printf '%s' "$out" | jq -c "$filt" 2>/dev/null)"
              }

              # Single tri-state line: map vpn-konform-bar's `class` to an `alt` key that
              # drives the vpn module's icon-map + color-map (on / connecting / off), tooltip
              # preserved. Replaces the old three-module hide-if-empty split — one module now
              # swaps icon + color by state. ("error" → off, matching the old behaviour.)
              vpn_line() {
                emit_line '{alt: (if .class == "connected" then "on" elif .class == "connecting" then "connecting" else "off" end), tooltip}' vpn-konform-bar status
              }

              # Pass treeman's text through unchanged: its waybar text is a compact
              # per-bucket "{glyph} {count}" line (configured via status.formats.icon in
              # ~/.config/treeman/config.yaml), so the bucket glyphs ARE the content. The
              # treeman custom module drops its own icon-name (config.toml) to avoid a
              # duplicate leading icon.
              treeman_line() { emit_line '.' treeman-status; }

              rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

              case "''${1:-}" in
                # treeman daemon streams lifecycle events; re-render status on each.
                # --all: global (status aggregates every repo; without it `logs tail`
                # auto-filters to the cwd, which for a bar widget is wrong/empty).
                # --since 1s: skip the default 50-event history replay. --json: machine form.
                treeman-watch)
                  treeman_line
                  treeman logs tail --follow --all --json --since 1s 2>/dev/null |
                    while IFS= read -r _; do treeman_line; done
                  ;;

                # VPN state changes from two sources, both event-driven:
                #   - the .connecting marker (inotify) → the in-flight "connecting" state
                #   - the oc-konform tunnel interface up/down (ip monitor) → connected /
                #     disconnected. The interface is the ground truth: systemd owns the
                #     openconnect process, and the kernel always reports the link edge.
                vpn-watch)
                  vpn_line
                  {
                    inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null &
                    ip monitor link 2>/dev/null &
                    wait
                  } | while IFS= read -r line; do
                    case "$line" in
                      openconnect-*.connecting | *oc-konform*) vpn_line ;;
                    esac
                  done
                  ;;

                # Submap indicator: the hl Lua submap (SUPER+R resize_mode) writes a tmpfs
                # marker on enter and removes it on exit (see src/hyprland/hyprland.lua), since
                # it isn't a native Hyprland submap the bar could observe. Show the mode name
                # while the marker exists, empty (hidden) otherwise.
                submap-watch)
                  marker="$rt/wayle-submap"
                  emit_submap() {
                    if [ -f "$marker" ]; then printf '{"text":"%s"}\n' "$(cat "$marker" 2>/dev/null)"; else echo; fi
                  }
                  emit_submap
                  inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null |
                    while IFS= read -r f; do
                      case "$f" in wayle-submap) emit_submap ;; esac
                    done
                  ;;

                # Keyboard-layout toast. xkb `grp:toggle` switches the layout internally
                # (no compositor keybind to hook), so listen to the compositor's event
                # stream and fire a transient OSD toast on every switch — the bar's
                # keyboard-input module already shows the persistent state. $2 = hypr.
                kb-toast)
                  case "''${2:-}" in
                    hypr)
                      sock="$rt/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
                      [ -S "$sock" ] || exit 0
                      # activelayout>>KEYBOARD,LAYOUT_NAME. Hyprland fires one event per
                      # keyboard at connect/startup; skip the first 3s so login is quiet.
                      start="$(date +%s)"
                      socat -U - "UNIX-CONNECT:$sock" 2>/dev/null | while IFS= read -r line; do
                        case "$line" in
                          activelayout\>\>*)
                            [ "$(($(date +%s) - start))" -lt 3 ] && continue
                            wayle toast "''${line##*,}" --icon ld-keyboard-symbolic --duration 1000 ;;
                        esac
                      done
                      ;;
                  esac
                  ;;

                *) exit 0 ;;
              esac
            '';
          })
        ]
        ++ (with pkgs; [
          hyprsunset
          inotify-tools
          iproute2
          brightnessctl
        ]);

        # The single file, never the directory: wayle writes into that directory
        # at runtime and home-manager refuses to overwrite it.
        xdg.configFile."wayle/config.toml" = {
          source =
            let
              c = pkgs.stubbe.withHash;
            in
            (pkgs.formats.toml { }).generate "wayle-config.toml" {
              general = {
                font-sans = "JetBrainsMono Nerd Font";
                font-mono = "JetBrainsMono Nerd Font";
              };

              styling = {
                theme-provider = "wayle";
                rounding = "sm";
                palette = {
                  bg = c.base;
                  surface = c.mantle;
                  elevated = c.surface0;
                  fg = c.text;
                  fg-muted = c.subtext0;
                  primary = c.mauve;
                  inherit (c) red;
                  inherit (c) yellow;
                  inherit (c) green;
                  inherit (c) blue;
                };
              };

              # The upstream default pam-service `system-auth` does not exist on
              # NixOS, so a dedicated /etc/pam.d/wayle is provisioned instead.
              lock = {
                pam-service = "wayle";
                lock-on-start = true;
                background-mode = "color";
                background-color = c.base;
                date-format = "%A, %d %B %Y";
              };

              bar = {
                location = "top";
                exclusive = true;
                rounding = "none";
                button-rounding = "none";
                button-group-rounding = "none";
                button-variant = "basic";
                scale = 1.0;
                button-icon-size = "20px";
                button-label-size = "14px";
                button-label-padding = "4px";
                button-gap = "4px";
                padding = "0px";
                padding-ends = "0px";
                module-gap = "4px";
                button-border-location = "none";

                layout = [
                  {
                    monitor = "*";
                    left = [
                      "hyprland-workspaces"
                      "custom-submap"
                    ];
                    center = [ "clock" ];
                    right = [
                      "mail"
                      "custom-treeman"
                      "keyboard-input"
                      "recorder"
                      "volume"
                      "microphone"
                      "brightness"
                    ]
                    ++ lib.optional hasBattery "battery"
                    ++ [
                      "network"
                      "bluetooth"
                      "hyprsunset"
                      "power-profiles"
                      "systray"
                      "custom-vpn"
                      "notifications"
                      "power"
                    ];
                  }
                ];
              };

              wallpaper = {
                engine-enabled = true;
                transition-type = "fade";
                transition-duration = 1.0;
                transition-fps = 60;
              };

              animations = {
                transition = "fade";
                notifications = {
                  enter = "bounce";
                  exit = "fade";
                };
              };

              osd = {
                enabled = true;
                text-align = "center";
              };

              modules = {
                clock.format = "%Y-%m-%d %H:%M";

                keyboard-input.layout-alias-map = {
                  "English (US)" = "EN";
                  "Danish" = "DA";
                  "Spanish" = "ES";
                  "Spanish (Spain)" = "ES";
                };

                # No `icon` in the map: it is shown regardless and would replace
                # the workspace number.
                hyprland-workspaces = {
                  display-mode = "label";
                  label-size = "14px";
                  workspace-map = {
                    "1".color = c.blue;
                    "2".color = "#f0c6c6";
                    "3".color = "#ddb6f2";
                    "4".color = "#f5bde6";
                    "5".color = "#f28d8c";
                    "6".color = "#e8a2a1";
                    "7".color = "#f8bd96";
                    "8".color = "#fae3b0";
                    "9".color = "#a6d189";
                    "10".color = "#81c8be";
                  };
                };

                systray.icon-scale = "20px";

                notifications.label-show = false;

                # label-show is all-or-nothing: showing a connected device name
                # would also show "Disconnected".
                bluetooth.label-show = false;

                volume = {
                  scroll-up = "wayle audio output-volume +5";
                  scroll-down = "wayle audio output-volume -5";
                  middle-click = "wayle audio output-mute";
                };

                microphone = {
                  scroll-up = "wayle audio input-volume +5";
                  scroll-down = "wayle audio input-volume -5";
                  middle-click = "wayle audio input-mute";
                };

                # wayle has no brightness CLI. -n keeps a 1-unit floor so
                # scrolling down never blacks the screen.
                brightness = {
                  scroll-up = "brightnessctl set 5%+";
                  scroll-down = "brightnessctl set 5%- -n";
                };

                weather = {
                  location = "55.6,12.5";
                  units = "metric";
                };

                # The power module has no built-in menu; every click action
                # defaults to a no-op unless bound.
                power.left-click = "wleave";

                recorder = {
                  icon-color = "fg-muted";
                  label-show = false;
                };

                mail = {
                  icon-name = "ld-mail-symbolic";
                  hide-when-zero = true;
                  notify = true;
                  notify-summary = "{{ sender }}";
                  notify-body = "{{ subject }}";
                  left-click = "dropdown:mail";
                  middle-click = "mail-open";
                  accounts = [
                    {
                      name = "Kontainer";
                      query = "folder:kontainer/INBOX and tag:unread";
                      provider = "outlook";
                    }
                    {
                      name = "Gmail";
                      query = "folder:gmail/INBOX and tag:unread";
                      provider = "gmail";
                    }
                  ];
                };

                hyprsunset = {
                  temperature = 4500;
                  auto-schedule = true;
                  latitude = 55.6;
                  longitude = 12.5;
                  label-show = false;
                  icon-on = "ld-moon-symbolic";
                  icon-off = "ld-sun-symbolic";
                };

                power-profiles = {
                  label-show = false;
                  left-click = ":cycle";
                  icon-power-saver = "ld-leaf-symbolic";
                  icon-balanced = "ld-scale-symbolic";
                  icon-performance = "ld-rocket-symbolic";
                  color-power-saver = "green";
                  color-balanced = "blue";
                  color-performance = "red";
                };

                custom = [
                  {
                    id = "submap";
                    mode = "watch";
                    restart-policy = "on-exit";
                    command = "wayle-widget submap-watch";
                    icon-name = "ld-layers-symbolic";
                    label-show = false;
                    hide-if-empty = true;
                  }
                  {
                    id = "treeman";
                    mode = "watch";
                    restart-policy = "on-exit";
                    command = "wayle-widget treeman-watch";
                    icon-show = false;
                    left-click = "treeman worktree list";
                    hide-if-empty = true;
                  }
                  {
                    id = "vpn";
                    mode = "watch";
                    restart-policy = "on-exit";
                    command = "wayle-widget vpn-watch";
                    label-show = false;
                    left-click = "vpn-konform-bar toggle";
                    icon-name = "ld-unplug-symbolic";
                    icon-map = {
                      on = "ld-lock-symbolic";
                      connecting = "ld-refresh-cw-symbolic";
                      off = "ld-unplug-symbolic";
                    };
                    color-map = {
                      on.icon-color = "green";
                      connecting = {
                        button-bg-color = "yellow";
                        icon-color = "bg-base";
                      };
                      off.icon-color = "fg-muted";
                    };
                  }
                ];
              };
            };
          force = true;
        };

        xdg.configFile."wleave/layout.json".source =
          let
            icon = name: "${pkgs.wleave}/share/wleave/icons/${name}.svg";
          in
          (pkgs.formats.json { }).generate "wleave-layout.json" {
            css = toString (
              pkgs.writeText "wleave.css" ''
                window {
                    background-color: rgba(12, 12, 12, 0.8);
                }

                button {
                    color: oklab(from var(--view-fg-color) var(--standalone-color-oklab));
                    background-color: var(--view-bg-color);
                    border: none;
                    padding: 10px;
                }

                /* Icon-only: collapse the text label. wleave always builds it from the
                   button's `text`, and a vertical box packs children from the top, so a
                   visible label pushes the icon up. Zeroing it leaves the picture as the
                   only space-taking child → it fills the button and ScaleDown centres
                   the glyph vertically. */
                button label.action-name {
                    font-size: 0;
                    min-height: 0;
                    min-width: 0;
                    margin: 0;
                    padding: 0;
                }

                button label.keybind {
                    font-size: 11px;
                    font-family: monospace;
                }

                button:hover label.keybind, button:focus label.keybind {
                    opacity: 1;
                }

                button:focus,
                button:hover {
                    background-color: color-mix(in srgb, var(--accent-bg-color), var(--view-bg-color));
                }

                button:active {
                    color: var(--accent-fg-color);
                    background-color: var(--accent-bg-color);
                }

                button#shutdown { --view-fg-color: #ff8d8d; }
                button#hibernate { --view-fg-color: #a8c0ff; }
                button#reboot { --view-fg-color: #84ffaa; }
                button#lock { --view-fg-color: #ffe8b6; }
                button#logout { --view-fg-color: #ffcca8; }
                button#suspend { --view-fg-color: #caaff9; }

                /* Shrink the icons: margin reduces the picture's allocation. */
                .icon-dropshadow {
                    margin: 10px;
                }
              ''
            );
            # Buttons always fill the inter-margin box, so margins are the only
            # size lever. Raise top/bottom to shrink the tiles further.
            "buttons-per-row" = "1/1";
            margin = "15%";
            "margin-top" = "46%";
            "margin-bottom" = "46%";
            "button-aspect-ratio" = "1";
            "close-on-lost-focus" = true;
            "no-version-info" = true;
            buttons = [
              {
                label = "lock";
                action = "wayle-lock";
                text = "Lock";
                keybind = "l";
                icon = icon "lock";
              }
              {
                label = "logout";
                action = [
                  {
                    "$DESKTOP_SESSION" = "hyprland";
                    shell = "hyprctl dispatch exit";
                  }
                  "loginctl terminate-user $USER"
                ];
                text = "Logout";
                keybind = "e";
                icon = icon "logout";
              }
              {
                label = "suspend";
                action = "systemctl suspend";
                text = "Suspend";
                keybind = "u";
                icon = icon "suspend";
              }
              {
                label = "reboot";
                action = "systemctl reboot";
                text = "Reboot";
                keybind = "r";
                icon = icon "reboot";
              }
              {
                label = "shutdown";
                action = "systemctl poweroff";
                text = "Shutdown";
                keybind = "s";
                icon = icon "shutdown";
              }
            ];
          };

        systemd.user.services = {
          wayle = {
            Unit = {
              Description = "Wayle desktop shell (bar, notifications, OSD, wallpaper)";
              Documentation = "https://github.com/stubbedev/wayle";
              After = sessionTarget ++ [ "power-profiles-daemon.service" ];
              Wants = [ "power-profiles-daemon.service" ];
              PartOf = sessionTarget;
              # Moves the unit hash on a config edit so sd-switch restarts wayle.
              X-Restart-Triggers = [ (toString config.xdg.configFile."wayle/config.toml".source) ];
            };
            Install.WantedBy = sessionTarget;
            Service = {
              # Not Type=dbus: systemd would block on org.freedesktop.Notifications
              # and time the unit out if wayle claims it late or not at all.
              Type = "simple";
              ExecStart = lib.getExe launcher;
              ExecStopPost = "-${lib.getExe pkgs.bash} -c '${lib.getExe' pkgs.procps "pkill"} -9 wayle || true; sleep 0.5'";
              Restart = "on-failure";
              RestartSec = "3s";
            };
          };

          await-powerprofile = awaitUnit "Restart the bar when power-profiles-daemon starts" "power-profiles-daemon.service";
          await-bluetooth = awaitUnit "Restart the bar when bluetooth starts" "bluetooth.service";
        };

        stubbe.setup.wayleLockPam = {
          privileged = true;
          title = "⚠️  Wayle lock PAM configuration missing";
          body = ''
            Wayle's session lock needs a PAM configuration to authenticate the
            unlock. This will create a minimal Nix-compatible PAM config that also
            unlocks the login keyring on unlock.
          '';
          script =
            let
              # Absolute path, never a bare module name: nix libpam resolves bare
              # names against the store securedir, and the host distro's module
              # cannot dlopen under nix's ld.so anyway.
              pamGnomeKeyring = "${config.home.profileDirectory}/lib/security/pam_gnome_keyring.so";
            in
            pkgs.stubbe.installText {
              name = "wayle-pam";
              target = "/etc/pam.d/wayle";
              text = ''
                #%PAM-1.0
                # gnome-keyring autounlock on the wayle session-lock unlock. Login on these
                # hosts is greetd *autologin* (no password entered), so the keyring never
                # PAM-unlocks at boot — the wayle unlock is the only place the login password
                # is typed, so it must unlock the keyring or Chrome et al. prompt on first use.
                #
                # pam_unix is `required` (not `sufficient`): a `sufficient` pass short-circuits
                # the auth stack and skips the gnome_keyring hook below it. `required` runs the
                # whole stack, so pam_unix collects the password (AUTHTOK) and gnome_keyring
                # reads it — the Arch `system-login` ordering. required-failure fails the stack,
                # so pam_deny is no longer needed. Mirrors NixOS enableGnomeKeyring.
                auth       required     pam_unix.so nullok
                auth       optional     ${pamGnomeKeyring}

                account    required     pam_unix.so

                password   required     pam_unix.so nullok
                password   optional     ${pamGnomeKeyring} use_authtok

                # No gnome_keyring session/auto_start line: the daemon is socket-activated by
                # systemd (gnome-keyring-daemon.socket). An auto_start here spawns a stray
                # `gnome-keyring-daemon --unlock` that rebinds $XDG_RUNTIME_DIR/keyring/control
                # out from under the real daemon — later unlocks then hit the stray while the
                # D-Bus secrets service stays locked. Auth-phase unlock via the control socket
                # is all the lock screen needs.
                session    required     pam_unix.so
              '';
            };
        };
      };
    };
}
