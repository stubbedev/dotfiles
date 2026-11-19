{ inputs, ... }:
let
  loginScreen = accent: wallpaper: {
    styling.palette.primary = accent;

    login = {
      background-mode = "image";
      background-image = wallpaper;
      date-format = "%A, %d %B %Y";
    };
  };
in
{
  flake.modules.nixos.lysShell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Nesting this in lib.mkIf makes the upstream modules and their options vanish.
      imports = [
        inputs.lys.nixosModules.lys-shell
        inputs.lys.nixosModules.lys-login
      ];

      config =
        let
          enabled = config.stubbe.userFeatures.lysShell && config.stubbe.userFeatures.lysWm;
        in
        lib.mkIf enabled {
          programs.lys-shell = {
            enable = true;
            package = pkgs.lys-shell;
            systemd.enable = false;
            settingsApp.package = pkgs.lys-settings;
            portal.enable = true;
          };

          programs.lys-login = {
            enable = true;
            package = pkgs.lys-login;
            lock.enable = true;
            greeter.settings =
              loginScreen pkgs.stubbe.withHash.mauve
                config.home-manager.users.${config.host.primaryUser}.stubbe.paths.wallpaper;
          };

          xdg.portal.config.common.default = [
            "lys-shell"
            "gnome"
            "gtk"
          ];
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
      enabled = config.features.lysShell && config.features.lysWm;

      lysShellBin = lib.getExe' pkgs.lys-shell "lys-shell";

      sessionTarget = [ config.wayland.systemd.target ];

      accent = pkgs.stubbe.withHash.mauve;

      loginScreenSettings = loginScreen accent config.stubbe.paths.wallpaper;

      app2unit = lib.getExe' pkgs.app2unit "app2unit";

      mailProviders = {
        kontainer = "outlook";
        gmail = "gmail";
      };

      mailAccounts =
        map
          (account: {
            name = lib.toSentenceCase account.name;
            query = "folder:${account.name}/${account.folders.inbox} and tag:unread";
            provider = mailProviders.${account.name} or "generic";
          })
          (
            lib.sort (a: b: a.primary || (!b.primary && a.name < b.name)) (
              lib.filter (account: account.notmuch.enable) (lib.attrValues config.accounts.email.accounts)
            )
          );
    in
    {
      imports = [ inputs.lys.homeModules.lys-polkit ];

      config = lib.mkIf enabled {
        services.lys-polkit = {
          enable = true;
          package = pkgs.lys-polkit;
        };

        home.packages = [ pkgs.lys-shell ];

        stubbe.zshCompletions._lys-shell = "${lysShellBin} completions zsh";

        xdg.configFile."autostart/nm-applet.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=NetworkManager Applet
          Hidden=true
        '';

        # The single file, never the directory: lys-shell writes into that directory
        # at runtime and home-manager refuses to overwrite it.
        xdg.configFile."lys-shell/config.yaml" = {
          source = pkgs.stubbe.gen.yaml "lys-shell-config.yaml" (
            lib.recursiveUpdate loginScreenSettings {
              # The upstream default pam-service `system-auth` does not exist on
              # NixOS, so a dedicated /etc/pam.d/lys-shell is provisioned instead.
              login.lock.pam-service = "lys-shell";

              idle.enable = false;

              bar = {
                inset-edge = "0px";
                inset-ends = "0px";
                rounding = "none";
                border-location = "none";
                padding = "2px";
                padding-ends = "4px";
                module-gap = "2px";

                layout = [
                  {
                    monitor = "*";
                    left = [
                      "lys-wm-workspaces"
                      "keybind-mode"
                    ];
                    center = [
                      "clock"
                      "mail"
                      "idle-inhibit"
                    ];
                    right = [
                      "keyboard-input"
                      "recorder"
                      "audio"
                      "brightness"
                    ]
                    ++ lib.optional config.host.battery "battery"
                    ++ [
                      "network"
                      "bluetooth"
                      "nightlight"
                      "power-profiles"
                      "systray"
                      "notifications"
                      "power"
                      "treeman"
                    ];
                  }
                ];
              };

              share-picker.default-page = "outputs";

              launcher = {
                inherit (config.stubbe.paths) terminal;
                matching = "fuzzy";
                sort = true;
                sorting-method = "fzf";
                drun = {
                  match-fields = [
                    "name"
                    "generic"
                    "keywords"
                  ];
                  show-actions = true;
                };
                run = {
                  run-command = "${app2unit} -- {cmd}";
                  shell-command = "${app2unit} -- {terminal} -e {cmd}";
                };
              };

              wallpaper = { inherit (config.stubbe.paths) wallpaper; };

              modules = {
                clock.format = "%Y-%m-%d %H:%M";

                keyboard-input.layout-alias-map = {
                  "English (US)" = "EN";
                  "Danish" = "DA";
                  "Spanish" = "ES";
                  "Spanish (Spain)" = "ES";
                };

                lys-wm-workspaces.display-mode = "label";

                notifications.label-show = false;

                # label-show is all-or-nothing: showing a connected device name
                # would also show "Disconnected".
                bluetooth.label-show = false;

                audio.right-click = "lys-shell audio input-mute";

                weather = {
                  location = "55.6,12.5";
                  units = "metric";
                };

                recorder = {
                  label-show = false;
                  microphone = true;
                  microphone-device = "alsa_input.usb-Creative_Technology_Ltd_Creative_Live__Cam_Sync_4K_SN0001-02.analog-stereo";
                  webcam-device = "/dev/video0";
                };

                mail = {
                  hide-when-zero = true;
                  notify = true;
                  notify-summary = "{{ sender }}";
                  notify-body = "{{ subject }}";
                  notify-click = "mail-open thread:{{ thread }}";
                  left-click = "dropdown:mail";
                  middle-click = "mail-open";
                  accounts = mailAccounts;
                };

                nightlight = {
                  temperature = 4500;
                  auto-schedule = true;
                  latitude = 55.6;
                  longitude = 12.5;
                  label-show = false;
                };

                power.suspend-command = "systemctl ${config.host.sleepVerb}";

                power-profiles = {
                  label-show = false;
                  left-click = ":cycle";
                };

                keybind-mode = {
                  auto-hide = true;
                  label-show = false;
                };
              };
            }
          );
          force = true;
        };

        stubbe.setup.lysShellLookReset.script =
          let
            runtimeConfig = "${config.xdg.configHome}/lys-shell/runtime.yaml";
            marker = "${config.xdg.stateHome}/lys-shell/look-reset-done";
            keepLookFree = ''
              del(.styling, .animations, .osd, .general.font-sans, .general.font-mono)
              | with(select(.bar != null); .bar |= with_entries(select(.key == "layout" or .key == "dropdown-autohide")))
              | with(select(.modules != null); .modules[] |= with_entries(select(.key | test("color|opacity|border|rounding|size|scale|padding|gap") | not)))
            '';
          in
          ''
            if [ ! -e ${lib.escapeShellArg marker} ]; then
              if [ -f ${lib.escapeShellArg runtimeConfig} ]; then
                ${lib.getExe pkgs.yq-go} ${lib.escapeShellArg keepLookFree} ${lib.escapeShellArg runtimeConfig} > ${lib.escapeShellArg "${runtimeConfig}.tmp"}
                mv ${lib.escapeShellArg "${runtimeConfig}.tmp"} ${lib.escapeShellArg runtimeConfig}
              fi
              mkdir -p ${lib.escapeShellArg (dirOf marker)}
              touch ${lib.escapeShellArg marker}
            fi
          '';

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
              # The Notifications activation file starts this unit; outside the
              # session that start fails at once instead of crash-looping a
              # shell that has no compositor to connect to.
              Requisite = sessionTarget;
              # Moves the unit hash on a config edit so sd-switch restarts lys-shell.
              X-Restart-Triggers = [ (toString config.xdg.configFile."lys-shell/config.yaml".source) ];
            };
            Install.WantedBy = sessionTarget;
            Service = {
              # Not Type=dbus: systemd would block on org.freedesktop.Notifications
              # and time the unit out if lys-shell claims it late or not at all.
              Type = "simple";
              Environment = [ "GDK_BACKEND=wayland" ];
              ExecStart = "${lysShellBin} shell";
              Restart = "on-failure";
              RestartSec = "3s";
            };
          };

        };
      };
    };
}
