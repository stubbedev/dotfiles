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
            portal.enable = true;
          };

          programs.lys-login = {
            enable = true;
            package = pkgs.lys-login;
            lock.enable = true;
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
        exes = [
          "lys-shell"
          "lys-settings"
        ];
      };

      lysShellBin = lib.getExe' lysShellPackage "lys-shell";

      # The shell starts the lock as `lys-login lock` from the PATH, so the lock
      # binary needs the same driver plumbing the shell itself gets.
      lysLoginPackage = gfx.bundle { pkg = pkgs.lys-login; };

      sessionTarget = [ config.wayland.systemd.target ];
    in
    {
      imports = [
        inputs.lys-shell.homeManagerModules.default
        inputs.lys-login.homeManagerModules.default
      ];

      config = lib.mkIf enabled {
        programs.lys-shell = lib.mkIf (config.host.platform != "nixos") {
          enable = true;
          package = lysShellPackage;
          systemd.enable = false;
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

        home.packages = [
          lysShellPackage
          (gfx.wrap pkgs.awww)
          (gfx.wrapExe "awww-daemon" pkgs.awww)
        ];

        stubbe.zshCompletions._lys-shell = "${lysShellBin} completions zsh";

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
                appearance = "dark";
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
              login = {
                lock = {
                  pam-service = "lys-shell";
                  lock-on-start = config.host.platform != "nixos";
                };
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
                lys-wm-workspaces = {
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
                  icon-color = "status-success";
                  label-color = "status-success";
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

                keybind-mode = {
                  auto-hide = true;
                  label-show = false;
                };
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
