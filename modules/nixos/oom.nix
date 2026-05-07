_: {
  flake.modules.nixos.oom =
    { ... }:
    {
      # Userspace OOM killer that fires before the kernel's last-resort
      # heuristic. Picks a smarter victim (highest oom_score under
      # memory pressure, not random root processes) and reacts at lower
      # thresholds. With zramSwap already in place, true OOM is rare,
      # but earlyoom keeps response time predictable when it hits.
      services.earlyoom = {
        enable = true;
        # Trigger when free RAM drops below 5% AND free swap below 10%.
        # Defaults are 10/10; tightened because zram swap compresses
        # ~3x so 10% nominal swap = ~30% effective.
        freeMemThreshold = 5;
        freeSwapThreshold = 10;
      };
    };
}
