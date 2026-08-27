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

      launcher = pkgs.stubbe.scriptBin {
        name = "wayle-launch";
        source = "src/wayle/launch.sh";
        vars = {
          # getExe' rather than getExe: the gfx symlinkJoin does not carry
          # meta.mainProgram, so name the binary explicitly.
          WAYLE = lib.getExe' waylePackage "wayle";
          # Applied to every monitor at startup. Single source of truth:
          # stubbe.paths.wallpaper, also exported as the WALLPAPER session
          # variable for the DRM-hotplug listener.
          WALLPAPER = config.stubbe.paths.wallpaper;
        };
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
          (pkgs.stubbe.scriptBin {
            name = "wayle-widget";
            source = "src/wayle/widget.sh";
          })
        ]
        ++ (with pkgs; [
          # Blue-light filter daemon. wayle's native hyprsunset module owns it —
          # spawning `hyprsunset -t/-g` at night on its own solar schedule and
          # killing it by day — so it only needs to be on PATH for the service.
          hyprsunset
          # inotifywait — the event-driven VPN widget (wayle-widget vpn-watch)
          # waits on the openconnect marker files instead of polling.
          inotify-tools
          # wayle has no brightness CLI, so the brightness module's scroll
          # actions shell out to this.
          brightnessctl
        ]);

        # Render config.toml — the single file, NOT the whole ~/.config/wayle
        # directory: wayle writes into that directory at runtime, so symlinking
        # the directory makes home-manager fail with "cannot overwrite
        # directory". @BATTERY@ becomes the battery module only where there is
        # one.
        xdg.configFile."wayle/config.toml" = {
          source = pkgs.stubbe.render "src/wayle/config.toml" {
            BATTERY = if hasBattery then "\"battery\"," else "";
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
          pkgs.writeText "wleave-layout.json" (
            builtins.toJSON {
              css = toString (pkgs.stubbe.file "src/wayle/wleave.css");
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
            }
          );

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
          script = pkgs.stubbe.installFile {
            # pam_gnome_keyring.so must be the nix-built module named by
            # absolute path (see the comment in src/wayle/pam). The profile path
            # is stable, so the rendered file only changes when the source does.
            source = pkgs.stubbe.render "src/wayle/pam" {
              PAM_GNOME_KEYRING = "${config.home.profileDirectory}/lib/security/pam_gnome_keyring.so";
            };
            target = "/etc/pam.d/wayle";
          };
        };
      };
    };
}
