{ self, ... }:
{
  flake.modules.nixos.powerSource =
    { config, pkgs, ... }:
    {
      # Reacts to the power source: PPD profile, and macOS-style adaptive
      # charging on top of the 80% cap from 85-battery-charge-threshold.rules.
      # See src/_shared/scripts/power-source.sh for what it decides and why.
      #
      # Non-NixOS counterpart:
      # modules/activation/privileged/setup-power-source.nix.

      # 0775 root:users so `battery-full` can drop the override flag without
      # sudo — the .path unit below turns that into an immediate run.
      systemd.tmpfiles.rules = [ "d /run/battery-charge 0775 root users -" ];

      systemd.services.power-source = {
        description = "Apply power-source policy (profile + charge threshold)";
        # Ordering only, no `wants`: the charging half still has work to do on a
        # host where power-profiles-daemon isn't running.
        after = [ "power-profiles-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "power-source";
        };
        # `script` rather than writeShellApplication: that wrapper forces
        # `set -e`, under which the "already at the wanted thresholds" guard
        # (`[ a = b ] && [ c = d ] && exit 0`) would abort the script whenever
        # it's false, which is the common path.
        path = with pkgs; [
          coreutils
          gawk
          power-profiles-daemon
        ];
        script = builtins.readFile (self + "/src/_shared/scripts/power-source.sh");
      };

      # Immediate reaction to plug/unplug — the timer alone would leave a
      # performance profile draining the battery for up to five minutes. Both
      # Mains and USB: with a USB-C-only charger the AC device may never fire an
      # event. --no-block keeps the udev worker free while the unit runs, and
      # this also fires on the boot coldplug, so no separate init unit.
      services.udev.extraRules =
        let
          run = "${config.systemd.package}/bin/systemctl --no-block start power-source.service";
        in
        ''
          SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${run}"
          SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="${run}"
        '';

      # Catches the approach of the usual unplug time. A run costs nothing: on
      # battery the script exits right after recording, and the profile half
      # only acts on a change.
      systemd.timers.power-source = {
        description = "Re-evaluate power-source policy";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          AccuracySec = "1min";
        };
      };

      # Makes `battery-full` take effect at once instead of at the next tick.
      systemd.paths.power-source-full = {
        description = "Watch for a manual charge-to-full request";
        wantedBy = [ "paths.target" ];
        pathConfig = {
          PathExists = "/run/battery-charge/full-now";
          Unit = "power-source.service";
        };
      };
    };
}
