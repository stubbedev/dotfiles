# Udev Rules

This directory contains udev rules for hardware device management.

## Files

### `rules.d/90-usb-audio-power.rules`

**Purpose:** Disables USB power management for audio devices to prevent audio popping and dropouts.

**What it does:**
- Sets `power/control` to `on` (disable autosuspend)
- Sets `power/autosuspend` to `-1` (never suspend)
- Applies to:
  - ThinkPad Thunderbolt 3 Dock Audio (specifically)
  - All USB Audio devices (generic rule)

**Why this matters:** USB autosuspend can cause audio devices to briefly suspend and resume, creating audible pops and clicks, especially when connected through docking stations and KVM switches.

## Installation

### System-wide installation (recommended)
```bash
sudo cp rules.d/90-usb-audio-power.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Verify it's working
```bash
# Find your USB audio device
lsusb | grep -i audio

# Check its power settings (example for ThinkPad dock)
# Find the device path
find /sys/bus/usb/devices -name "*17ef:306a*" -type d

# Check power settings (should show "on" and "-1")
cat /sys/bus/usb/devices/*/power/control
cat /sys/bus/usb/devices/*/power/autosuspend
```

## Troubleshooting

If the rules don't apply:
1. Ensure the file is in `/etc/udev/rules.d/`
2. Check for syntax errors: `udevadm test $(udevadm info -q path -n /dev/snd/controlC1)`
3. Reload rules: `sudo udevadm control --reload-rules`
4. Trigger device events: `sudo udevadm trigger`
5. Unplug and replug the USB device

## Notes

- These rules apply at device connection time
- Changes persist across reboots
- May slightly increase power consumption (negligible for desktop setups)
- Does not affect battery-powered devices when on battery (governed by other power management settings)
