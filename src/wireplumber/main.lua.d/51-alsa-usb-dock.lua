-- ALSA configuration for USB docks with KVM switches
-- General ALSA configuration (keep default buffer sizes)
table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "node.name", "matches", "alsa_output.*" },
    },
    {
      { "node.name", "matches", "alsa_input.*" },
    },
  },
  apply_properties = {
    ["api.alsa.period-size"] = 256,
    ["api.alsa.headroom"] = 1024,
    ["api.alsa.disable-batch"] = true,
    ["session.suspend-timeout-seconds"] = 0,  -- Disable suspend (0 = never suspend)
    ["api.alsa.use-chmap"] = false,  -- Disable channel mapping for USB devices
    ["audio.rate"] = 48000,  -- Force 48kHz to avoid resampling
    ["node.pause-on-idle"] = false,  -- Don't pause when idle (prevents pops)
    ["audio.no-dsp"] = true,  -- Skip DSP processing to reduce latency spikes
  },
})

-- Specific rule for USB audio devices (like Thunderbolt dock)
-- Slightly increased buffers for USB dock through KVM switch
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
    ["api.alsa.period-size"] = 1024,  -- Increased for USB dock stability
    ["api.alsa.headroom"] = 2048,
    ["api.alsa.disable-batch"] = false,  -- Enable batching for USB
    ["session.suspend-timeout-seconds"] = 0,
    ["node.pause-on-idle"] = false,
    ["audio.rate"] = 48000,
  },
})
