-- ALSA configuration for USB docks with KVM switches
-- Only apply to USB audio devices (Thunderbolt dock)
-- Increased buffers for USB dock through KVM switch to prevent popping
table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "api.alsa.card.driver", "equals", "USB-Audio" },
    },
    {
      { "alsa.driver_name", "equals", "snd_usb_audio" },
    },
  },
  apply_properties = {
    ["api.alsa.period-size"] = 4096,  -- Quadrupled for maximum stability with KVM switch
    ["api.alsa.period-num"] = 2,      -- Number of periods in buffer
    ["api.alsa.headroom"] = 8192,     -- Quadrupled headroom for additional safety margin
    ["api.alsa.disable-batch"] = false,  -- Enable batching for USB
    ["session.suspend-timeout-seconds"] = 0,  -- Never suspend
    ["node.pause-on-idle"] = false,   -- Never pause when idle
    ["audio.rate"] = 48000,
    ["api.alsa.use-chmap"] = false,   -- Disable channel mapping for stability
    ["resample.quality"] = 4,         -- Medium quality resampling (lower CPU)
  },
})
