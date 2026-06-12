_: {
  # Home-manager's switch DOES NOT prune old generations — the
  # ~/.local/state/nix/profiles/{home-manager,profile,channels}-N-link
  # symlinks accumulate forever and pin every store path they reference,
  # which is by far the biggest source of /nix/store bloat on a host
  # that rebuilds many times a day. We fix that with two pieces:
  #
  #   1. An activation hook that trims the per-user profiles to
  #      "current + 1 previous" on every `home-manager switch`. Running
  #      it from activation (rather than only a timer) means a switch
  #      cleans up after itself, matching the user's expectation.
  #
  #   2. A weekly systemd-user timer that runs `nix-collect-garbage`
  #      to actually free the store paths whose last GC root we just
  #      removed. Gated on non-NixOS hosts: on NixOS the system-level
  #      nix-gc.service (modules/nixos/nix-gc.nix) handles collection.
  flake.modules.homeManager.nixGc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      isNixos = config.host.platform == "nixos";
      profilesDir = "${config.home.homeDirectory}/.local/state/nix/profiles";
      pruneScript = pkgs.writeShellScript "hm-nix-prune-generations" ''
        set -eu
        for profile in home-manager profile channels; do
          target="${profilesDir}/$profile"
          if [ -e "$target" ]; then
            ${pkgs.nix}/bin/nix-env --profile "$target" --delete-generations +2 || true
          fi
        done
      '';
    in
    {
      home.activation.pruneNixGenerations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pruneScript}
      '';

      systemd.user = lib.mkIf (!isNixos) {
        services.nix-collect-garbage = {
          Unit.Description = "Collect unreachable nix store paths";
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.nix}/bin/nix-collect-garbage";
          };
        };

        timers.nix-collect-garbage = {
          Unit.Description = "Weekly nix store garbage collection";
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
            Unit = "nix-collect-garbage.service";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
