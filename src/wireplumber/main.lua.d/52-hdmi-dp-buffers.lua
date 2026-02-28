-- ALSA configuration for HDMI/DisplayPort audio through KVM switches
-- DisplayPort audio through KVM/monitor chains requires massive buffers
-- due to additional latency from DP encoding/decoding and KVM switch jitter

table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "node.name", "matches", "alsa_output.*HDMI*" },
    },
    {
      { "node.name", "matches", "alsa_output.*DisplayPort*" },
    },
    {
      { "alsa.id", "matches", "HDMI*" },
    },
  },
  apply_properties = {
    ["api.alsa.period-size"] = 8192,  -- Maximum buffer for DP through KVM
    ["api.alsa.period-num"] = 3,      -- 3 periods for extra safety
    ["api.alsa.headroom"] = 16384,    -- Double headroom for DP jitter
    ["api.alsa.disable-batch"] = false,  -- Enable batching
    ["session.suspend-timeout-seconds"] = 0,  -- Never suspend
    ["node.pause-on-idle"] = false,   -- Never pause when idle
    ["audio.rate"] = 48000,
    ["api.alsa.use-chmap"] = false,   -- Disable channel mapping
    ["resample.quality"] = 4,         -- Medium quality resampling
  },
})
