_: {
  flake.modules.nixos.nixGc =
    { ... }:
    {
      # Weekly cleanup of generations older than 30d, plus dedup of
      # identical store paths. Keeps /nix from filling the disk on a
      # long-running install without manual intervention.
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };

      nix.optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };

      # Flake-only system: nix-channel CLI + the channel update timer
      # are dead weight. Disable so a stale `nix-channel --update` cron
      # can't drift the system away from the flake.lock pin.
      nix.channel.enable = false;
    };
}
