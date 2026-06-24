_: {
  flake.modules.nixos.nixGc =
    { config, ... }:
    {
      # Garbage-collect the store on a weekly timer. We want the system
      # profile trimmed to "current + 1 previous" so a rebuild that boots
      # poorly can still be rolled back instantly, but we don't want
      # months of stale generations holding 100s of GB live.
      #
      # `nix-collect-garbage` only deletes store paths that have no
      # remaining GC roots. Old generation symlinks ARE roots, so we
      # have to prune them BEFORE collecting — otherwise the GC has
      # nothing to free. `--delete-older-than` is time-based and lets
      # generation count drift; `nix-env --delete-generations +2`
      # enforces a count regardless of switch frequency.
      nix = {
        gc = {
          automatic = true;
          dates = "weekly";
          options = "";
        };

        optimise = {
          automatic = true;
          dates = [ "weekly" ];
        };

        # Flake-only system: nix-channel CLI + the channel update timer
        # are dead weight. Disable so a stale `nix-channel --update` cron
        # can't drift the system away from the flake.lock pin.
        channel.enable = false;
      };

      # The gc/optimise timers are weekly + Persistent, so a run missed while
      # the machine was off fires at the NEXT boot — `nix-gc` alone takes ~3.5min
      # of saturated disk IO, which starves SDDM + the Hyprland compositor and
      # leaves the desktop (bar/wallpaper) blank for ~90s after login. Pin both
      # to idle IO/CPU scheduling so they yield to anything interactive: login
      # stays fast and the maintenance still completes in the background.
      systemd.services.nix-gc.serviceConfig = {
        ExecStartPre = [
          "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +2"
        ];
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };
      systemd.services.nix-optimise.serviceConfig = {
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };

      # Also prune on every `nixos-rebuild switch` so generations don't
      # accumulate between weekly GC runs — same pattern as the
      # home-manager activation hook in modules/home/nix-gc.nix.
      system.activationScripts.pruneSystemGenerations = {
        text = ''
          ${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +2 || true
        '';
      };
    };
}
