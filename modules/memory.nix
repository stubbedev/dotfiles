_:
let
  memorySysctl = {
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
    "kernel.sysrq" = 240;
  };

  thrashingTmpfiles = "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000";

  oomdMemoryPressure = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "80%";
  };

  oomdSlices = {
    "-" = oomdMemoryPressure // {
      ManagedOOMSwap = "kill";
    };
    system = oomdMemoryPressure;
    user = oomdMemoryPressure;
  };

  oomdUserSlice = {
    Slice = oomdMemoryPressure;
  };

  oomKillMessages = {
    d989611b15e44c9dbf31e3c81256e4ed = "systemd-oomd";
    fe6faa94e7774663a0da52717891d8ef = "the kernel OOM killer";
  };
in
{
  flake.modules.nixos.memory =
    { lib, pkgs, ... }:
    {
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
      };

      boot.kernel.sysctl = memorySysctl;

      systemd = {
        tmpfiles.rules = [ thrashingTmpfiles ];
        oomd.enable = true;
        slices = lib.mapAttrs (_: sliceConfig: { inherit sliceConfig; }) oomdSlices;
        user.units.slice = {
          text = pkgs.stubbe.gen.unitText oomdUserSlice;
          overrideStrategy = "asDropin";
        };
      };
    };

  flake.modules.homeManager.memory =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      oomNotify = pkgs.stubbe.bashApp {
        name = "oom-notify";
        runtimeInputs = with pkgs; [
          systemd
          jq
          libnotify
        ];
        text = ''
          journalctl --user --follow --lines=0 --output=json \
            ${lib.concatMapStringsSep " " (id: "MESSAGE_ID=${id}") (lib.attrNames oomKillMessages)} |
            jq --unbuffered --raw-output \
              --argjson killers ${lib.escapeShellArg (builtins.toJSON oomKillMessages)} \
              'select(.USER_UNIT | endswith(".slice") | not) | [.USER_UNIT, $killers[.MESSAGE_ID]] | @tsv' |
            while IFS=$'\t' read -r unit killer; do
              name=$unit
              if [[ $unit =~ ^app-[^-]+-(.+)-[0-9a-f]{8}\.scope$ || $unit =~ ^app-[^-]+-(.+)@[0-9a-f]+\.service$ ]]; then
                name=''${BASH_REMATCH[1]}
              fi
              notify-send --urgency=critical --app-name="Out of memory" \
                "Killed $name" "$killer stopped $unit to free memory"
            done
        '';
      };
    in
    {
      systemd.user.services.oom-notify = lib.mkIf config.features.desktop {
        Unit = {
          Description = "Desktop notification when an OOM killer stops a unit";
          After = [ config.wayland.systemd.target ];
          PartOf = [ config.wayland.systemd.target ];
        };
        Install.WantedBy = [ config.wayland.systemd.target ];
        Service = {
          ExecStart = lib.getExe oomNotify;
          Restart = "on-failure";
          RestartSec = "2s";
        };
      };

    };
}
