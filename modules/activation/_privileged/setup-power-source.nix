{ self, ... }:
{
  # NixOS deploys this via modules/nixos/power-source.nix. This activation is
  # the non-NixOS counterpart and is gated off on NixOS by mkSudoSetupModule.
  enableIf = { config, ... }: config.features.desktop;
  args =
    { lib, homeLib, ... }:
    let
      script = "/usr/local/sbin/power-source.sh";
      unit = "power-source.service";

      toUnit = lib.generators.toINI { listsAsDuplicateKeys = true; };

      service = toUnit {
        Unit = {
          Description = "Apply power-source policy (profile + charge threshold)";
          # Ordering only, no Wants: the charging half still has work to do on a
          # host where power-profiles-daemon isn't running.
          After = "power-profiles-daemon.service";
        };
        Service = {
          Type = "oneshot";
          ExecStart = script;
          StateDirectory = "power-source";
        };
      };

      # Catches the approach of the usual unplug time. A run costs nothing: on
      # battery the script exits right after recording, and the profile half
      # only acts on a change.
      timer = toUnit {
        Unit.Description = "Re-evaluate power-source policy";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          AccuracySec = "1min";
        };
        Install.WantedBy = "timers.target";
      };

      # Makes `battery-full` take effect at once instead of at the next tick.
      path = toUnit {
        Unit.Description = "Watch for a manual charge-to-full request";
        Path = {
          PathExists = "/run/battery-charge/full-now";
          Unit = unit;
        };
        Install.WantedBy = "paths.target";
      };
    in
    homeLib.mkInstallPrompt {
      subject = "power-source policy (profile + adaptive charging)";
      preCheck = homeLib.requirePath "/sys/class/power_supply/BAT0/charge_control_end_threshold";
      body = ''
        Two things that should follow the charger, and don't on their own:

        - power-profiles-daemon never switches by itself, so a "performance"
          profile picked while docked keeps draining after the undock. This
          drops to power-saver on unplug and back to performance on AC — only
          on an actual change, so a profile you pick by hand still sticks.
        - macOS-style Optimized Battery Charging. The 80% cap stays where it
          is; this learns what time of day the charger actually comes out and
          raises the ceiling to 100% for the two hours before that, so the
          machine is full when you leave without sitting at 100% all week.
          Until a few unplugs are on record it just holds at 80%.

        Also installs `battery-full`, the "charge to full now" override — it
        lasts until you unplug.
      '';
      actionScript = ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        sudo install -d -m 0755 /usr/local/sbin /etc/tmpfiles.d /etc/udev/rules.d

        ${homeLib.installSystemFile {
          target = script;
          mode = "0755";
          content = builtins.readFile (self + "/src/_shared/scripts/power-source.sh");
        }}

        # 0775 root:users so `battery-full` can drop the override flag without
        # sudo — the .path unit turns that into an immediate run.
        ${homeLib.installSystemFile {
          target = "/etc/tmpfiles.d/power-source.conf";
          content = ''
            d /run/battery-charge 0775 root users -
          '';
        }}

        # Immediate reaction to plug/unplug — the timer alone would leave a
        # performance profile draining the battery for up to five minutes.
        # Mirror of the rule in modules/nixos/power-source.nix, with FHS paths.
        ${homeLib.installSystemFile {
          target = "/etc/udev/rules.d/85-power-source.rules";
          content = ''
            SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemctl --no-block start ${unit}"
            SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemctl --no-block start ${unit}"
          '';
        }}

        ${homeLib.installSystemFile {
          target = "/etc/systemd/system/${unit}";
          content = service;
        }}

        ${homeLib.installSystemFile {
          target = "/etc/systemd/system/power-source.timer";
          content = timer;
        }}

        ${homeLib.installSystemFile {
          target = "/etc/systemd/system/power-source-full.path";
          content = path;
        }}

        sudo systemd-tmpfiles --create /etc/tmpfiles.d/power-source.conf >/dev/null 2>&1 || true
        sudo systemctl daemon-reload
        sudo systemctl enable --now power-source.timer power-source-full.path >/dev/null 2>&1 || true

        # Reload rules so the next plug event picks them up. No trigger: see
        # setup-usb-autosuspend-disable.nix for why re-running power_supply
        # add events on this machine is a bad idea.
        if command -v udevadm >/dev/null 2>&1; then
          sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        fi
      '';
    };
}
