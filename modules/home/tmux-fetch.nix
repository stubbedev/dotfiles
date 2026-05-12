_: {
  flake.modules.homeManager.tmuxFetch =
    {
      config,
      lib,
      pkgs,
      scripts,
      ...
    }:
    lib.mkIf config.features.desktop {
      systemd.user.services.tmux-fetch-repos = {
        Unit = {
          Description = "Background-fetch every git repo open in tmux";
          # Network may not be ready right at login; the script no-ops if the
          # remote is unreachable, but we still avoid the first fire being a
          # guaranteed miss.
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          # tmux + git need to be on PATH for the script. Pulling them in by
          # store path avoids depending on whatever PATH the user-manager
          # happened to inherit at login.
          Environment = [
            "PATH=${
              lib.makeBinPath [
                pkgs.tmux
                pkgs.git
                pkgs.coreutils
              ]
            }"
          ];
          ExecStart = "${scripts.tmux-fetch-repos}/bin/tmux-fetch-repos";
          # Stay out of the way of interactive work.
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.tmux-fetch-repos = {
        Unit.Description = "Fetch tmux repos every 5 minutes";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          # Spread fires by up to 30s so multiple machines / resumes don't
          # all hammer the same remote at the same wall-clock instant.
          RandomizedDelaySec = "30s";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
