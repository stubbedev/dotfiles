{ inputs, lib, ... }:
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
      imports = [ inputs.lys.nixosModules.lys-power ];

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
      # The battery module and lys-power read the battery (and wireless
      # peripherals' charge) from UPower.
      services.upower.enable = true;

      # These apply only while no lys-wm session runs: lys-wm holds the
      # handle-lid-switch inhibitor and applies the same policy itself,
      # including undocking or unplugging with the lid already closed,
      # which logind alone never acts on (systemd#7690).
      services.logind.settings.Login = lidSwitch;

      services.lys-power.enable = true;
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
          text = "exec ${lib.getExe pkgs.lys-power} full";
        })
      ];
    };
}
