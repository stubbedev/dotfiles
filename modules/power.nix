{ lib, ... }:
let
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];

  logindWatchdogSec = "15min";

  nmWake = {
    description = "Wake NetworkManager after resume";
    after = sleepTargets ++ [ "NetworkManager.service" ];
    busctlArgs = "call org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Sleep b false";
  };

  intelHybridModels = {
    alder-lake = [
      151
      154
    ];
    raptor-lake = [
      183
      186
      191
    ];
    meteor-lake = [
      170
      172
    ];
    lunar-lake = [ 189 ];
    panther-lake = [ 204 ];
  };

  intelHybridCase = lib.concatMapStringsSep " | " toString (
    lib.sort (a: b: a < b) (lib.concatLists (lib.attrValues intelHybridModels))
  );

  cpuModel =
    awk: ''$(${awk} -F: '/^model[[:space:]]*:/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)'';

  apmDescription = "Adaptive battery charging and power profile policy";
  apmAfter = [
    "power-profiles-daemon.service"
    "upower.service"
  ];
  apmService = {
    StateDirectory = "adaptive-power-manager";
    Restart = "on-failure";
    RestartSec = "10s";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ "/sys/class/power_supply" ];
    ProtectHome = true;
    PrivateTmp = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
  };
  apmWantedBy = "graphical.target";

  chargeFlagTmpfiles = "d /run/battery-charge 0775 root users -";

  lidSwitch = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
in
{
  flake.modules.nixos.power =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.intel-lpmd.enable = config.host.battery;

      systemd.services.intel_lpmd.serviceConfig.ExecCondition = lib.mkIf config.host.battery (
        pkgs.writeShellScript "intel-hybrid-cpu" ''
          case "${cpuModel (lib.getExe pkgs.gawk)}" in
          ${intelHybridCase}) exit 0 ;;
          esac
          exit 1
        ''
      );

      systemd.services.systemd-logind.serviceConfig.WatchdogSec = logindWatchdogSec;

      systemd.services.nm-wake-after-resume = {
        inherit (nmWake) description after;
        wantedBy = sleepTargets;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "-${lib.getExe' config.systemd.package "busctl"} ${nmWake.busctlArgs}";
        };
      };

      services.power-profiles-daemon.enable = true;
      # The battery module and adaptive-power-manager read the battery
      # (and wireless peripherals' charge) from UPower.
      services.upower.enable = true;

      # These apply only while no lys-wm session runs: lys-wm holds the
      # handle-lid-switch inhibitor and applies the same policy itself,
      # including undocking or unplugging with the lid already closed,
      # which logind alone never acts on (systemd#7690).
      services.logind.settings.Login = lidSwitch;

      # For the CLI (status, full) in user shells; the daemon runs from its
      # own store path below.
      environment.systemPackages = [ pkgs.adaptive-power-manager ];

      # battery-full's flag directory: group-writable so the user CLI can
      # drop a charge-to-full request without sudo.
      systemd.tmpfiles.rules = [ chargeFlagTmpfiles ];

      # Event-driven: UPower signals cover every AC edge, inotify the
      # battery-full flag, and the daemon's own wall-clock timer the
      # prediction boundaries. No systemd timer, no udev trigger.
      # graphical.target, not multi-user: ppd is After=multi-user.target,
      # so ordering after it from multi-user is a cycle systemd breaks by
      # dropping this unit.
      systemd.services.adaptive-power-manager = {
        description = apmDescription;
        after = apmAfter;
        wantedBy = [ apmWantedBy ];
        serviceConfig = apmService // {
          ExecStart = "${lib.getExe pkgs.adaptive-power-manager} run";
        };
      };
    };

  flake.modules.homeManager.power =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.packages = [
        (pkgs.stubbe.bashApp {
          name = "battery-full";
          text = "exec ${lib.getExe pkgs.adaptive-power-manager} full";
        })
      ];
    };
}
