-- ALSA configuration for USB docks with KVM switches
-- Only apply to USB audio devices (Thunderbolt dock)
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
