_: {
  flake.modules.nixos.zram =
    { ... }:
    {
      # Compressed RAM swap — no disk cost, kicks in under memory pressure
      # and keeps OOM-killer at bay during big rebuilds. zstd compresses
      # ~3x on typical workloads, so 50% of RAM ≈ 1.5x extra effective.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 50;
      };
    };
}
