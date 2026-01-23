-- Disable Bluetooth headset profile autoswitch (keeps A2DP active)
if bluez_monitor ~= nil then
  bluez_monitor.properties = bluez_monitor.properties or {}
  bluez_monitor.properties["bluez5.autoswitch-profile"] = false
end
