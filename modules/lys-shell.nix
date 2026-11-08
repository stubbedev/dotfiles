{ inputs, ... }:
let
  greeterConfigPath = "/etc/lys-shell/config.yaml";

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
        inputs.lys-shell.nixosModules.default
        inputs.lys-login.nixosModules.default
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
      inherit (config.stubbe) gfx;
      enabled = config.features.lysShell && config.features.lysWm;

      # Rejoined with the upstream package so $out/share reaches the profile:
      # without it GTK cannot resolve lys-shell's bundled icon names.
      lysShellPackage = gfx.bundle {
        pkg = pkgs.lys-shell;
        exes = [ "lys-shell" ];
      };

      lysShellBin = lib.getExe' lysShellPackage "lys-shell";

      # The shell starts the lock as `lys-login lock` from the PATH, so the lock
      # binary needs the same driver plumbing the shell itself gets.
      lysLoginPackage = gfx.bundle { pkg = pkgs.lys-login; };

      sessionTarget = [ config.wayland.systemd.target ];

      accent = pkgs.stubbe.withHash.mauve;

      loginScreenSettings = loginScreen accent config.stubbe.paths.wallpaper;

      app2unit = lib.getExe' pkgs.app2unit "app2unit";
    in
    {
      imports = [
        inputs.lys-shell.homeManagerModules.default
        inputs.lys-login.homeManagerModules.default
        inputs.lys-polkit.homeManagerModules.default
      ];

      config = lib.mkIf enabled {
        programs.lys-shell = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          package = lysShellPackage;
          systemd.enable = false;
          settingsApp.package = gfx.bundle { pkg = pkgs.lys-settings; };
          settings = { };
          portal.enable = true;
        };

        # The system module provisions the lock's PAM service on NixOS; on a
        # foreign distro the privileged setup step below does it, so only the
        # binary is enabled here.
        programs.lys-login = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          package = lysLoginPackage;
        };

        services.lys-polkit = {
          enable = true;
          package = pkgs.lys-polkit;
        };

        home.packages = [
          lysShellPackage
        ];

        stubbe.zshCompletions._lys-shell = "${lysShellBin} completions zsh";

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
                      "volume"
                      "microphone"
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

                nightlight = {
                  temperature = 4500;
                  auto-schedule = true;
                  latitude = 55.6;
                  longitude = 12.5;
                  label-show = false;
                };

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

        stubbe.setup.lysLoginGreeterConfig = {
          privileged = true;
          title = "Theming the lys-login greeter";
          body = ''
            The greeter runs as lys-greeter and reads only ${greeterConfigPath},
            so this installs the lock screen's wallpaper and date format there.
          '';
          stateInputs = [ greeterConfigPath ];
          script = pkgs.stubbe.setup.file {
            source = pkgs.stubbe.gen.yaml "lys-greeter-config.yaml" loginScreenSettings;
            target = greeterConfigPath;
          };
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

        stubbe.setup.lysShellLockPam = {
          privileged = true;
          title = "⚠️  lys-shell lock PAM configuration missing";
          body = ''
            lys-shell's session lock needs a PAM configuration to authenticate the
            unlock. This will create a minimal Nix-compatible PAM config.
          '';
          script = pkgs.stubbe.setup.text {
            name = "lys-shell-pam";
            target = "/etc/pam.d/lys-shell";
            text = ''
              #%PAM-1.0
              auth       required     pam_unix.so nullok

              account    required     pam_unix.so

              password   required     pam_unix.so nullok

              session    required     pam_unix.so
            '';
          };
        };
      };
    };
}
