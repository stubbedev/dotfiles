-- Enable HDMI/DisplayPort audio by unmuting IEC958 switches
-- These switches control digital audio output (SPDIF/HDMI)

table.insert(alsa_monitor.rules, {
  matches = {
    {
      { "node.name", "matches", "alsa_output.*hdmi*" },
    },
  },
  apply_properties = {
    -- Enable IEC958 digital output switches for HDMI audio
    ["api.alsa.use-acp"] = true,
    ["session.suspend-timeout-seconds"] = 0,
  },
})

-- ALSA UCM (Use Case Manager) configuration for HDMI
-- This ensures IEC958 switches are enabled when HDMI outputs are used
alsa_monitor.properties = {
  ["alsa.reserve"] = false,
}
