_: {
  flake.modules.homeManager.packagesWaylandTools =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      enabled = config.features.hyprland || config.features.niri;

      # Custom wleave layout: backs wayle's `power` widget (left-click =
      # "wleave"). The bundled default locks with gtklock/swaylock (neither
      # installed here) and has no hyprland logout branch, so override:
      #   - lock   → `wayle-lock` (wayle's native ext-session-lock locker)
      #   - logout → compositor-specific, with a universal loginctl fallback
      # Icons are reused from the wleave package's own share dir.
      wleaveIcon = name: "${pkgs.wleave}/share/wleave/icons/${name}.svg";

      # Icons are a GtkPicture (ContentFit::ScaleDown) that fills the button's
      # inner box, so they scale with the button and end up oversized. Setting
      # `css` REPLACES wleave's default sheet (it doesn't merge), so this is the
      # bundled default verbatim plus one rule: margin around the picture
      # (.icon-dropshadow) shrinks the icon's allocation → smaller icon without
      # touching button/label size. Bump the margin to shrink icons further.
      wleaveStyle = pkgs.writeText "wleave-style.css" ''
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
      '';

      wleaveLayout = pkgs.writeText "wleave-layout.json" (
        builtins.toJSON {
          css = toString wleaveStyle;
          # wleave is a fullscreen layer-shell window. Buttons ALWAYS fill the
          # inter-margin box (layout.rs maximises button area; aspect-ratio only
          # changes their shape, not their size), so the only size lever is the
          # margins. Margins accept a percentage of the viewport per-axis
          # (units.rs), so this is resolution-independent.
          #
          # Single row of small square tiles, centred:
          #   - "1/1" → all buttons on one row
          #   - top/bottom 46% → ~8% of screen height free → tiny buttons (this
          #     is what makes them ~4x smaller; raise the % to shrink further)
          #   - left/right 15% → ample width for the row, so it just centres
          #   - aspect "1" → square tiles
          "buttons-per-row" = "1/1";
          margin = "15%";
          "margin-top" = "46%";
          "margin-bottom" = "46%";
          "button-aspect-ratio" = "1";
          "close-on-lost-focus" = true;
          # Drop the "Wleave x.y. Missing or broken icons?" footer label.
          "no-version-info" = true;
          buttons = [
            {
              label = "lock";
              action = "wayle-lock";
              text = "Lock";
              keybind = "l";
              icon = wleaveIcon "lock";
            }
            {
              label = "logout";
              action = [
                {
                  "$DESKTOP_SESSION" = "niri";
                  shell = "niri msg action quit --skip-confirmation";
                }
                {
                  "$DESKTOP_SESSION" = "hyprland";
                  shell = "hyprctl dispatch exit";
                }
                # Works on any systemd-logind session regardless of compositor.
                "loginctl terminate-user $USER"
              ];
              text = "Logout";
              keybind = "e";
              icon = wleaveIcon "logout";
            }
            {
              label = "suspend";
              action = "systemctl suspend";
              text = "Suspend";
              keybind = "u";
              icon = wleaveIcon "suspend";
            }
            {
              label = "reboot";
              action = "systemctl reboot";
              text = "Reboot";
              keybind = "r";
              icon = wleaveIcon "reboot";
            }
            {
              label = "shutdown";
              action = "systemctl poweroff";
              text = "Shutdown";
              keybind = "s";
              icon = wleaveIcon "shutdown";
            }
          ];
        }
      );
    in
    lib.mkIf enabled {
      # wleave reads $XDG_CONFIG_HOME/wleave/layout.json; style.css falls back
      # to the package's bundled default automatically.
      xdg.configFile."wleave/layout.json".source = wleaveLayout;

      home.packages = with pkgs; [
        # Graphical power menu (GTK4 layer-shell) backing wayle's power widget.
        (homeLib.gfx wleave)

        # Screen lock is wayle's native ext-session-lock locker (`wayle lock`);
        # no separate locker package.

        # Idle daemon (ext-idle-notify-v1)
        hypridle

        # Blue-light filter daemon. wayle's native hyprsunset module owns it —
        # it spawns `hyprsunset -t/-g` at night on its own solar schedule and
        # kills it by day — so it only needs to be on PATH for the wayle service.
        hyprsunset
        # IPC glue for several scripts that talk to compositor/daemon sockets
        # (hy3 tiling, jetbrains popup resize, wayle widget helpers).
        socat

        # Color picker (screencopy protocol)
        (homeLib.gfx hyprpicker)

        # Cursor theme tool
        hyprcursor

        # Polkit authentication agent (standard D-Bus polkit)
        hyprpolkitagent

        # Wayland debug/inspection tools
        wlprop
        wayland-utils

        # Nested single-app Wayland compositor — useful for debugging
        # screen-locking, kiosk-style apps without locking the host session.
        (homeLib.gfx cage)
      ];
    };
}
