{ inputs, ... }:
{
  flake.modules.nixos.lysShell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Nesting this in lib.mkIf makes the upstream module and its options vanish.
      imports = [ inputs.lys-shell.nixosModules.default ];

      config =
        let
          enabled = config.stubbe.userFeatures.lysShell && config.stubbe.userFeatures.hyprland;
        in
        lib.mkIf enabled {
          programs.lys-shell = {
            enable = true;
            package = pkgs.lys-shell;
            systemd.enable = false;
            portal.enable = true;
            lock.enable = true;
          };

          # programs.hyprland registers a per-desktop portal section that beats
          # common.default, so mkForce is needed to drop it.
          xdg.portal.config = lib.mkForce {
            common.default = [
              "lys-shell"
              "gnome"
              "gtk"
            ];
          };
        };
    };

  flake.modules.homeManager.lysShell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      enabled = config.features.lysShell && config.features.hyprland;

      # Rejoined with the upstream package so $out/share reaches the profile:
      # without it GTK cannot resolve lys-shell's bundled icon names.
      lysShellPackage = gfx.bundle {
        pkg = pkgs.lys-shell;
        exes = [
          "lys-shell"
          "lys-settings"
        ];
      };

      hasBattery =
        let
          psu = /. + "/sys/class/power_supply";
        in
        builtins.pathExists psu
        && lib.any (lib.hasPrefix "BAT") (builtins.attrNames (builtins.readDir psu));

      lysShellBin = lib.getExe' lysShellPackage "lys-shell";

      launcher = pkgs.stubbe.bashApp {
        name = "lys-shell-launch";
        text = ''
          set +e +u +o pipefail

          shopt -s nullglob

          uid=$(id -u)
          runtime="''${XDG_RUNTIME_DIR:-/run/user/$uid}"

          ${pkgs.stubbe.hypr.instanceFn}
          CURRENT_INSTANCE=""
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            CURRENT_INSTANCE=$(hypr_instance first 1 "")
          fi
          if [ -z "$CURRENT_INSTANCE" ] && [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
            CURRENT_INSTANCE=$(hypr_instance first 50 0.1)
          fi

          if [ -n "$CURRENT_INSTANCE" ]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
          fi

          _wayland_live() {
            local display="$1"
            [ -S "$runtime/$display" ] || return 1
            [ -e "$runtime/$display.lock" ] || return 1
            ! flock -n -x "$runtime/$display.lock" true 2>/dev/null
          }

          if [ -n "$WAYLAND_DISPLAY" ] && _wayland_live "$WAYLAND_DISPLAY"; then
            :
          else
            unset WAYLAND_DISPLAY
            attempt=0
            while [ $attempt -lt 50 ] && [ -z "$WAYLAND_DISPLAY" ]; do
              for socket in "$runtime"/wayland-[0-9]*; do
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

          exec ${lysShellBin} shell
        '';
      };

      sessionTarget = [ "hyprland-session.target" ];

      restartBarIfSessionActive = pkgs.stubbe.shellScript "restart-bar-if-session-active" ''
        if ${lib.getExe' pkgs.systemd "systemctl"} --user is-active --quiet ${lib.head sessionTarget}; then
          exec ${lib.getExe' pkgs.systemd "systemctl"} --user restart lys-shell.service
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
      imports = [ inputs.lys-shell.homeManagerModules.default ];

      config = lib.mkIf enabled {
        home.activation.lysShellStateFromWayle = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          oldState="${config.xdg.stateHome}/wayle"
          newState="${config.xdg.stateHome}/lys-shell"
          if [ -d "$oldState" ]; then
            run mkdir -p "$newState"
            for entry in "$oldState"/*; do
              [ -e "$entry" ] || continue
              case "$entry" in *.log) continue ;; esac
              [ -e "$newState/''${entry##*/}" ] || run mv "$entry" "$newState/"
            done
          fi
        '';

        programs.lys-shell = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          package = lysShellPackage;
          systemd.enable = false;
          settings = { };
          portal.enable = true;
        };

        home.packages = [
          lysShellPackage
          launcher
          (gfx.wrap pkgs.awww)
          (gfx.wrapExe "awww-daemon" pkgs.awww)
          (pkgs.stubbe.bashApp {
            name = "lys-shell-widget";
            text = ''
              set +e
              set -uo pipefail

              emit_line() {
                local filt="$1" out
                shift
                out="$("$@" 2>/dev/null)" || { echo; return; }
                [ -n "$out" ] || { echo; return; }
                printf '%s\n' "$(printf '%s' "$out" | jq -c "$filt" 2>/dev/null)"
              }

              rt="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

              case "''${1:-}" in
                submap-watch)
                  marker="$rt/lys-shell-submap"
                  emit_submap() {
                    if [ -f "$marker" ]; then printf '{"text":"%s"}\n' "$(cat "$marker" 2>/dev/null)"; else echo; fi
                  }
                  emit_submap
                  inotifywait -q -m -e create,delete,close_write,moved_to,moved_from --format '%f' "$rt" 2>/dev/null |
                    while IFS= read -r f; do
                      case "$f" in lys-shell-submap) emit_submap ;; esac
                    done
                  ;;

                kb-toast)
                  case "''${2:-}" in
                    hypr)
                      sock="$rt/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
                      [ -S "$sock" ] || exit 0
                      start="$(date +%s)"
                      socat -U - "UNIX-CONNECT:$sock" 2>/dev/null | while IFS= read -r line; do
                        case "$line" in
                          # wtype & friends spawn a throwaway hl-virtual-keyboard-*
                          # and emit `,none` on teardown: not a layout switch.
                          activelayout\>\>hl-virtual-keyboard-*) continue ;;
                          activelayout\>\>*)
                            [ "$(($(date +%s) - start))" -lt 3 ] && continue
                            lys-shell toast "''${line##*,}" --icon ld-keyboard-symbolic --duration 1000 ;;
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
          brightnessctl
        ]);

        # The single file, never the directory: lys-shell writes into that directory
        # at runtime and home-manager refuses to overwrite it.
        xdg.configFile."lys-shell/config.yaml" = {
          source =
            let
              c = pkgs.stubbe.withHash;
            in
            pkgs.stubbe.gen.yaml "lys-shell-config.yaml" {
              general = {
                font-sans = "JetBrainsMono Nerd Font";
                font-mono = "JetBrainsMono Nerd Font";
              };

              styling = {
                theme-provider = "lys-shell";
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
              # NixOS, so a dedicated /etc/pam.d/lys-shell is provisioned instead.
              lock = {
                pam-service = "lys-shell";
                lock-on-start = true;
                background-mode = "image";
                background-image = config.stubbe.paths.wallpaper;
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
                    center = [
                      "clock"
                      "idle-inhibit"
                    ];
                    right = [
                      "mail"
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
                      "notifications"
                      "power"
                      "treeman"
                    ];
                  }
                ];
              };

              greeter.background-mode = "wallpaper";

              share-picker.default-page = "outputs";

              wallpaper = {
                inherit (config.stubbe.paths) wallpaper;
                fit-mode = "fill";
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
                  workspace-map = builtins.listToAttrs (
                    lib.imap1 (i: hex: {
                      name = toString i;
                      value.color = "#${hex}";
                    }) pkgs.stubbe.workspaceColors
                  );
                };

                systray.icon-scale = "20px";

                notifications.label-show = false;

                # label-show is all-or-nothing: showing a connected device name
                # would also show "Disconnected".
                bluetooth.label-show = false;

                volume = {
                  scroll-up = "lys-shell audio output-volume +5";
                  scroll-down = "lys-shell audio output-volume -5";
                  middle-click = "lys-shell audio output-mute";
                };

                microphone = {
                  scroll-up = "lys-shell audio input-volume +5";
                  scroll-down = "lys-shell audio input-volume -5";
                  middle-click = "lys-shell audio input-mute";
                };

                # lys-shell has no brightness CLI. -n keeps a 1-unit floor so
                # scrolling down never blacks the screen.
                brightness = {
                  scroll-up = "brightnessctl set 5%+";
                  scroll-down = "brightnessctl set 5%- -n";
                };

                weather = {
                  location = "55.6,12.5";
                  units = "metric";
                };

                recorder = {
                  icon-color = "fg-muted";
                  label-show = false;
                  microphone = true;
                  microphone-device = "alsa_input.usb-Creative_Technology_Ltd_Creative_Live__Cam_Sync_4K_SN0001-02.analog-stereo";
                  webcam-device = "/dev/video0";
                };

                mail = {
                  icon-name = "ld-mail-symbolic";
                  icon-color = "accent";
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
                    command = "lys-shell-widget submap-watch";
                    icon-name = "ld-layers-symbolic";
                    label-show = false;
                    hide-if-empty = true;
                  }
                ];
              };
            };
          force = true;
        };

        xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".source =
          (pkgs.formats.ini { }).generate "org.freedesktop.Notifications.service"
            {
              "D-BUS Service" = {
                Name = "org.freedesktop.Notifications";
                Exec = "${lib.getExe' pkgs.coreutils "false"}";
                SystemdService = "lys-shell.service";
              };
            };

        systemd.user.services = {
          lys-shell = {
            Unit = {
              Description = "lys-shell desktop shell (bar, notifications, OSD, wallpaper)";
              Documentation = "https://github.com/stubbedev/lys-shell";
              After = sessionTarget ++ [ "power-profiles-daemon.service" ];
              Wants = [ "power-profiles-daemon.service" ];
              PartOf = sessionTarget;
              # Moves the unit hash on a config edit so sd-switch restarts lys-shell.
              X-Restart-Triggers = [ (toString config.xdg.configFile."lys-shell/config.yaml".source) ];
            };
            Install.WantedBy = sessionTarget;
            Service = {
              # Not Type=dbus: systemd would block on org.freedesktop.Notifications
              # and time the unit out if lys-shell claims it late or not at all.
              Type = "simple";
              ExecStart = lib.getExe launcher;
              ExecStopPost = "-${lib.getExe pkgs.bash} -c '${lib.getExe' pkgs.procps "pkill"} -9 lys-shell || true; sleep 0.5'";
              Restart = "on-failure";
              RestartSec = "3s";
            };
          };

          await-powerprofile = awaitUnit "Restart the bar when power-profiles-daemon starts" "power-profiles-daemon.service";
          await-bluetooth = awaitUnit "Restart the bar when bluetooth starts" "bluetooth.service";
        };

        stubbe.setup.lysShellLockPam = {
          privileged = true;
          title = "⚠️  lys-shell lock PAM configuration missing";
          body = ''
            lys-shell's session lock needs a PAM configuration to authenticate the
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
            pkgs.stubbe.setup.text {
              name = "lys-shell-pam";
              target = "/etc/pam.d/lys-shell";
              text = ''
                #%PAM-1.0
                auth       required     pam_unix.so nullok
                auth       optional     ${pamGnomeKeyring}

                account    required     pam_unix.so

                password   required     pam_unix.so nullok
                password   optional     ${pamGnomeKeyring} use_authtok

                session    required     pam_unix.so
              '';
            };
        };
      };
    };
}
