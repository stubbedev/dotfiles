# wayle — the desktop shell. One Rust/GTK4 daemon that replaced waybar +
# swaync + hyprpaper, and is also the session lock, the xdg-desktop-portal
# backend, and the blue-light scheduler.
#
# Consequences worth knowing before editing anything here:
#   * Notifications are wayle's. Do not push notify-send from other modules;
#     set the templates in config.toml instead.
#   * The lock is wayle's native ext-session-lock-v1 implementation, which needs
#     a PAM service named "wayle" (provisioned by the NixOS module, or by the
#     activation below).
#   * hyprsunset is wayle's to spawn and kill on its solar schedule, so it is
#     only on PATH — never autostarted from hyprland.lua.
{ inputs, ... }:
{
  # wayle is the portal backend on NixOS. The upstream module registers the
  # system-level xdg.portal and the D-Bus-activated
  # xdg-desktop-portal-wayle user service; the SHELL itself still runs from the
  # HM user service below, so systemd.enable stays off.
  flake.modules.nixos.wayle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # imports must be top-level and unconditional — nesting them inside
      # lib.mkIf makes the upstream module (and options.programs.wayle) vanish.
      # The module is inert until programs.wayle.enable, which only the gated
      # block below sets.
      imports = [ inputs.wayle.nixosModules.default ];

      config =
        let
          enabled = config.stubbe.userFeatures.wayle && config.stubbe.userFeatures.hyprland;
        in
        lib.mkIf enabled {
          programs.wayle = {
            enable = true;
            # Native GL on NixOS, so the bare overlay package is right here —
            # the HM-level nixGL wrap is a passthrough on NixOS anyway. This
            # package backs the xdg-desktop-portal-wayle service.
            package = pkgs.wayle;
            # The shell runs from the HM user service; do not let the module
            # spawn a second `wayle shell`.
            systemd.enable = false;
            portal.enable = true;
            # Provision /etc/pam.d/wayle so the native ext-session-lock unlock
            # can authenticate (NixOS has no system-auth). config.toml sets
            # lock.pam-service = "wayle" to match.
            lock.enable = true;
            # No greeter: login is greetd autologin straight into Hyprland
            # (modules/hyprland.nix).
          };

          # Route every interface to wayle. programs.hyprland registers its own
          # per-desktop portal section, and that section beats a plain
          # common.default for the Hyprland session — mkForce replaces the whole
          # attr, dropping the per-desktop section so every session falls
          # through to this common block. wayle implements every impl.portal
          # interface (Secret included), so no gnome-keyring carve-out is
          # needed; gnome/gtk stay only as dormant fallbacks.
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

      # symlinkJoin the nixGL-wrapped binaries back with the upstream package so
      # $out/share survives into the profile. That puts wayle's bundled icons
      # (share/icons/hicolor/scalable/actions, 364 cm-*-symbolic SVGs) on
      # XDG_DATA_DIRS where GTK's hicolor fallback resolves the
      # from_icon_name() lookups — no hand-populated ~/.local/share/wayle/icons
      # — and exposes the wayle-settings .desktop entry. Both GTK4 binaries get
      # the GL wrap.
      waylePackage = gfx.bundle {
        pkg = pkgs.wayle;
        exes = [
          "wayle"
          "wayle-settings"
        ];
      };

      # Does this machine have a battery? Read /sys impurely — the flake already
      # runs --impure. Used to drop the battery module from the bar on desktops.
      hasBattery =
        let
          psu = /. + "/sys/class/power_supply";
        in
        builtins.pathExists psu
        && lib.any (lib.hasPrefix "BAT") (builtins.attrNames (builtins.readDir psu));

      # getExe' rather than getExe: the gfx symlinkJoin does not carry
      # meta.mainProgram, so name the binary explicitly.
      wayleBin = lib.getExe' waylePackage "wayle";

      # Launch wayle with proper Wayland environment detection.
      # Sets HYPRLAND_INSTANCE_SIGNATURE only when an active Hyprland socket is
      # found; on niri (or any other Wayland compositor) we skip Hyprland
      # detection and proceed — wayle's hyprland modules just stay inactive.
      #
      # Fork-minimal: globs instead of ls|grep, var expansion instead of
      # dirname/basename, a single id -u. flock and sleep are the only forks
      # left — they are the liveness primitive and the retry backoff.
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

      # Bounce the bar when a service it reads from comes up late. Guarded on
      # the session being live so it is a no-op outside a graphical login.
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
      # Same reasoning as the NixOS half: the upstream module has to be imported
      # unconditionally, and every effect sits behind `enable`.
      imports = [ inputs.wayle.homeManagerModules.default ];

      config = lib.mkIf enabled {
        # Standalone (non-NixOS) home-manager: register wayle as the portal
        # backend at the USER level — the .portal interface declaration, the
        # D-Bus activation file, a generic portals.conf routing every interface
        # to wayle, and the xdg-desktop-portal-wayle user service. On NixOS the
        # system module above owns the portal, so this is gated off there to
        # avoid registering the backend twice.
        programs.wayle = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          # GTK4 portal dialogs need the same nixGL wrap the shell uses.
          # Identical derivation, so home-manager's profile dedupes the two
          # references.
          package = waylePackage;
          systemd.enable = false;
          # config.toml is rendered below; leave settings empty so the module
          # does not also write it.
          settings = { };
          portal.enable = true;
        };

        home.packages = [
          waylePackage
          launcher
          # wayle's wallpaper engine shells out to awww (which ships awww +
          # awww-daemon); without it `wayle wallpaper set` fails with "neither
          # awww nor swww found in PATH".
          (gfx.wrap pkgs.awww)
          (gfx.wrapExe "awww-daemon" pkgs.awww)
          # Graphical power menu (GTK4 layer-shell) backing wayle's power widget.
          (gfx.wrap pkgs.wleave)
          # Reshapes the status scripts' JSON for wayle's custom modules: drops
          # the nerd-font glyph (wayle shows icon-name instead), keeps the value.
          #
          # Every mode is event-driven (wayle `mode = "watch"`): emit the current
          # line, then re-emit on each real state change — no polling. Sources:
          #   treeman     `treeman logs tail --follow` event stream
          #   vpn-watch   inotify on the openconnect marker files
          #   submap      tmpfs marker written by the hl Lua resize submap
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
          # Blue-light filter daemon. wayle's native hyprsunset module owns it —
          # spawning `hyprsunset -t/-g` at night on its own solar schedule and
          # killing it by day — so it only needs to be on PATH for the service.
          hyprsunset
          # inotifywait — the event-driven VPN widget (wayle-widget vpn-watch)
          # waits on the openconnect marker files instead of polling — and
          # `ip monitor link` is its second event source.
          inotify-tools
          iproute2
          # wayle has no brightness CLI, so the brightness module's scroll
          # actions shell out to this.
          brightnessctl
        ]);

        # Render config.toml — the single file, NOT the whole ~/.config/wayle
        # directory: wayle writes into that directory at runtime, so symlinking
        # the directory makes home-manager fail with "cannot overwrite
        # directory". The palette comes from pkgs.stubbe.withHash, and the
        # battery module joins the bar only where there is one. Full schema:
        # wayle docs under docs/config/ upstream, or https://wayle.app/config/.
        xdg.configFile."wayle/config.toml" = {
          source =
            let
              c = pkgs.stubbe.withHash;
            in
            (pkgs.formats.toml { }).generate "wayle-config.toml" {
              general = {
                # waybar rendered everything in JetBrainsMono Nerd Font; match that
                # for both UI text and mono so the bar reads identically.
                font-sans = "JetBrainsMono Nerd Font";
                font-mono = "JetBrainsMono Nerd Font";
              };

              styling = {
                # Static palette (no wallpaper-derived theming) so colors stay
                # Catppuccin. Rounded dropdowns/popovers/OSD/dialogs (the bar itself
                # stays flat — bar.rounding/button-rounding = "none").
                theme-provider = "wayle";
                rounding = "sm";
                # bg=base, surface=mantle (the waybar bar color), elevated=surface0.
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

              # Session lock (replaces hyprlock). Wayle locks natively via
              # ext-session-lock-v1, in response to `wayle lock`, the logind Lock
              # signal, or the shell IPC. The config default pam-service
              # `system-auth` doesn't exist on NixOS; /etc/pam.d/wayle is
              # provisioned by programs.wayle.lock (NixOS) or the wayleLockPam
              # setup below. Login is greetd autologin with no password at boot
              # (modules/hyprland.nix), so the shell self-locks on start — the
              # session comes up locked and gates on the password.
              lock = {
                pam-service = "wayle";
                lock-on-start = true;
                # Solid Catppuccin base, matching the old hyprlock background.
                background-mode = "color";
                background-color = c.base;
                date-format = "%A, %d %B %Y";
              };

              bar = {
                location = "top";
                exclusive = true;
                # Flat bar — no border radius anywhere (bar, buttons, groups).
                rounding = "none";
                button-rounding = "none";
                button-group-rounding = "none";
                # "basic" = icon+label, minimal background (no colored pill).
                button-variant = "basic";
                # Bar flush to the screen edge (padding = padding-ends = 0), but
                # widgets keep their INTERNAL padding — button-label-padding is the
                # margin around each button's icon+label, NOT the bar-edge gap. px
                # sizes are ABSOLUTE (bypass `scale`). With bar padding 0 the bar
                # height is the tallest button = button-icon-size +
                # 2*button-label-padding = 20 + 2*4 = 28. `scale` stays for
                # HORIZONTAL inter-widget spacing only.
                scale = 1.0;
                button-icon-size = "20px";
                button-label-size = "14px";
                button-label-padding = "4px";
                # Gap between a widget's icon and its label. Pinned in px — the
                # lone scale default rendered as no visible gap. Auto-suppressed
                # when a widget has no label.
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
                    # Clock centered as the focal point; everything else right,
                    # grouped by purpose: activity → audio/hardware →
                    # connectivity → system → tray → vpn → notifications → power.
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

              # Wallpaper (replaces hyprpaper + awww): same image on every
              # monitor. [[wallpaper.monitors]] only does per-connector overrides,
              # so the all-monitor wallpaper is applied at startup via
              # `wayle wallpaper set <path>` in wayle-launch.
              wallpaper = {
                engine-enabled = true;
                # Animate wallpaper changes (and the startup set) with a fade.
                transition-type = "fade";
                transition-duration = 1.0;
                transition-fps = 60;
              };

              # Transient-surface animations. Global `transition` is the fallback
              # (OSD + toasts fade); notifications bounce in and fade out.
              animations = {
                transition = "fade";
                notifications = {
                  enter = "bounce";
                  exit = "fade";
                };
              };

              # OSD (waybar had no volume/brightness overlay). text-align centers
              # the toast/toggle content (the keyboard-layout toast).
              osd = {
                enabled = true;
                text-align = "center";
              };

              modules = {
                # waybar showed an ISO-ish date + 24h time.
                clock.format = "%Y-%m-%d %H:%M";

                # Short keyboard layout labels.
                keyboard-input.layout-alias-map = {
                  "English (US)" = "EN";
                  "Danish" = "DA";
                  "Spanish" = "ES";
                  "Spanish (Spain)" = "ES";
                };

                # Show workspace NUMBERS (display-mode = "label"). The
                # workspace-map sets only `color` per workspace — NOT `icon`: a map
                # `icon` is "shown regardless" and would replace the number.
                # `color` is the active-workspace background; the number itself is
                # colored by the module's active/occupied/empty-color. Hyprland IDs
                # are stable 1-10 so the map lands.
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

                # Match the other modules' 20px icon content. Pinned in px;
                # internal-padding is horizontal-only on a top bar, so the tray
                # contributes only its icon height.
                systray.icon-scale = "20px";

                # Drop the "00" count label — the bell icon already conveys state
                # (bell / bell-dot when unread / bell-off for DND).
                notifications.label-show = false;

                # Icon-only (the icon differs connected/disconnected); keeps the
                # native dropdown. label-show is all-or-nothing, so a connected
                # device name can't be shown without also showing "Disconnected".
                bluetooth.label-show = false;

                # Scroll to adjust volume, middle-click to mute (left-click still
                # opens the audio dropdown).
                volume = {
                  scroll-up = "wayle audio output-volume +5";
                  scroll-down = "wayle audio output-volume -5";
                  middle-click = "wayle audio output-mute";
                };

                # Mic: scroll to adjust input level, middle-click to mute.
                microphone = {
                  scroll-up = "wayle audio input-volume +5";
                  scroll-down = "wayle audio input-volume -5";
                  middle-click = "wayle audio input-mute";
                };

                # Brightness: scroll to adjust backlight. wayle has no brightness
                # CLI (unlike audio), so scroll shells out to brightnessctl. -n
                # keeps a 1-unit floor so scrolling down never blacks the screen.
                brightness = {
                  scroll-up = "brightnessctl set 5%+";
                  scroll-down = "brightnessctl set 5%- -n";
                };

                # Weather: powers the clock's right-click dropdown (no bar
                # module). Coords are Copenhagen (kept in sync with hyprsunset);
                # open-meteo needs no API key.
                weather = {
                  location = "55.6,12.5";
                  units = "metric";
                };

                # wayle's power module is a bare button with NO built-in menu —
                # every click action defaults to "" (no-op). Bind it to wleave,
                # the GTK4 power menu installed + configured above.
                power.left-click = "wleave";

                # Native GStreamer recorder. left-click toggles capture,
                # right-click opens the options dropdown; SUPER+SHIFT+R also
                # toggles it (hyprland.lua). button-variant = "basic" renders a
                # transparent background, so the module's red bg defaults never
                # paint; recording state shows via the icon swap. Colors are
                # static per the schema, so the icon is a neutral fg-muted
                # instead of the loud always-red default. Flip label-show = true
                # for an elapsed timer while recording.
                recorder = {
                  icon-color = "fg-muted";
                  label-show = false;
                };

                # Built-in mail module — notmuch count + inotify maildir watch
                # (event-driven, no poll). `accounts` gives the per-account unread
                # breakdown in the native dropdown with brand icons; the bar count
                # is their sum. Native `notify` fires one notify-send per newly
                # arrived message. Placeholders: {{ sender }}, {{ subject }},
                # {{ count }}, {{ new }}.
                mail = {
                  icon-name = "ld-mail-symbolic";
                  # Collapse the slot at zero unread.
                  hide-when-zero = true;
                  notify = true;
                  notify-summary = "{{ sender }}";
                  notify-body = "{{ subject }}";
                  # left-click opens the native per-account dropdown.
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

                # Blue-light filter — wayle's native module (Hyprland only). It
                # owns the hyprsunset daemon and computes the sunrise/sunset
                # schedule from the coords (GeoClue overrides when available). A
                # click sets a manual override until the next solar boundary.
                # Icon-only: moon while the filter is on, sun when off.
                hyprsunset = {
                  temperature = 4500;
                  auto-schedule = true;
                  latitude = 55.6;
                  longitude = 12.5;
                  label-show = false;
                  icon-on = "ld-moon-symbolic";
                  icon-off = "ld-sun-symbolic";
                };

                # Built-in power-profiles module: power-profiles-daemon D-Bus
                # backend, per-profile icon + color, cycles profiles on
                # left-click natively. saver=green, balanced=blue,
                # performance=red. Icon-only to match the right cluster.
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

                # Custom modules: the status scripts emit waybar JSON
                # ({text,tooltip,class}); wayle's custom module parses that
                # natively. All are event-driven watchers (wayle-widget above).
                custom = [
                  # Submap indicator (icon-only). The hl Lua resize_mode isn't a
                  # native Hyprland submap, so hyprland.lua writes/removes a tmpfs
                  # marker on enter/exit and this watches it — shows only while in
                  # a submap (e.g. SUPER+R), hidden otherwise.
                  {
                    id = "submap";
                    mode = "watch";
                    restart-policy = "on-exit";
                    command = "wayle-widget submap-watch";
                    icon-name = "ld-layers-symbolic";
                    label-show = false;
                    hide-if-empty = true;
                  }
                  # Event-driven: re-renders on each treeman daemon lifecycle
                  # event. icon-show = false: treeman's text is a compact
                  # per-bucket "{glyph} {count}" line, so the bucket glyphs carry
                  # the icon; dropping icon-name alone still reserves a blank
                  # icon slot.
                  {
                    id = "treeman";
                    mode = "watch";
                    restart-policy = "on-exit";
                    command = "wayle-widget treeman-watch";
                    icon-show = false;
                    left-click = "treeman worktree list";
                    # treeman emits nothing when idle → collapse the slot.
                    hide-if-empty = true;
                  }
                  # VPN: one tri-state icon-only module. The watcher emits `alt` =
                  # on/connecting/off; icon-map + color-map swap the icon AND its
                  # colors per state. Old waybar look preserved: green lock
                  # connected, yellow-bg refresh connecting, grey unplug
                  # disconnected.
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

        # wleave: our own layout, because the bundled default locks with
        # gtklock/swaylock (neither installed) and has no hyprland logout
        # branch. Icons are reused from the wleave package's own share dir.
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
            # wleave is a fullscreen layer-shell window whose buttons ALWAYS
            # fill the inter-margin box (layout.rs maximises button area;
            # aspect-ratio only changes their shape, not their size), so the
            # only size lever is the margins — which accept a percentage of
            # the viewport per axis, making this resolution-independent.
            #
            # One row of small square tiles, centred: "1/1" puts every button
            # on one row, top/bottom 46% leaves ~8% of screen height (this is
            # what makes them ~4x smaller — raise it to shrink further),
            # left/right 15% just centres the row, aspect "1" squares them.
            "buttons-per-row" = "1/1";
            margin = "15%";
            "margin-top" = "46%";
            "margin-bottom" = "46%";
            "button-aspect-ratio" = "1";
            "close-on-lost-focus" = true;
            # Drop the "Wleave x.y. Missing or broken icons?" footer.
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
                  # Works on any systemd-logind session, as a fallback.
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
              # Bump the unit hash when the config store path moves, so
              # sd-switch restarts wayle on a config edit.
              X-Restart-Triggers = [ (toString config.xdg.configFile."wayle/config.toml".source) ];
            };
            Install.WantedBy = sessionTarget;
            Service = {
              # Type=simple, not dbus: wayle is a full shell, not solely a
              # notification daemon. It claims
              # org.freedesktop.Notifications during shell startup, and
              # Type=dbus+BusName would make systemd block on that name and time
              # the whole unit out if it is claimed late or notifications are
              # disabled.
              Type = "simple";
              ExecStart = lib.getExe launcher;
              ExecStopPost = "-${lib.getExe pkgs.bash} -c '${lib.getExe' pkgs.procps "pkill"} -9 wayle || true; sleep 0.5'";
              Restart = "on-failure";
              RestartSec = "3s";
            };
          };

          # Independent of the session target: these run under default.target
          # and exist only to bounce the bar once their dependency is up.
          await-powerprofile = awaitUnit "Restart the bar when power-profiles-daemon starts" "power-profiles-daemon.service";
          await-bluetooth = awaitUnit "Restart the bar when bluetooth starts" "bluetooth.service";
        };

        # Non-NixOS half of programs.wayle.lock.enable: wayle's native
        # ext-session-lock unlock authenticates against this PAM service, and
        # config.toml sets lock.pam-service = "wayle" to match.
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
              # Absolute nix path, never a bare module name: wayle is a nix
              # binary, so its libpam resolves bare names against the nix store
              # securedir (where only pam_unix et al. live), and the host
              # distro's module can't dlopen anyway (host-only deps like
              # libselinux aren't visible to nix's ld.so). The profile path is
              # stable across upgrades and GC-rooted via gnome-keyring in
              # home.packages.
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
