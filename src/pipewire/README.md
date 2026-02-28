# PipeWire Configuration

<!--toc:start-->
- [PipeWire Configuration](#pipewire-configuration)
  - [Files](#files)
    - [`pipewire.conf.d/99-usb-dock.conf`](#pipewireconfd99-usb-dockconf)
    - [`pipewire-pulse.conf.d/99-usb-dock.conf`](#pipewire-pulseconfd99-usb-dockconf)
    - [`pulse-client.conf`](#pulse-clientconf)
  - [WirePlumber Configuration](#wireplumber-configuration)
    - [`../wireplumber/main.lua.d/51-alsa-usb-dock.lua`](#wireplumbermainluad51-alsa-usb-docklua)
  - [Applying Changes](#applying-changes)
  - [Troubleshooting](#troubleshooting)
    - [Check current settings](#check-current-settings)
    - [List audio devices](#list-audio-devices)
    - [Check if USB autosuspend is disabled (should be -1)](#check-if-usb-autosuspend-is-disabled-should-be-1)
<!--toc:end-->

This directory contains PipeWire audio configuration optimized for various hardware setups.

## Files

### `pipewire.conf.d/99-usb-dock.conf`

Optimized configuration for USB audio devices connected through docking stations and KVM switches.

**Purpose:** Eliminates audio popping/crackling caused by:
- USB communication latency
- KVM switch electrical noise and timing jitter
- Additional latency from dock USB hubs

**Settings:**
- Sample rate: 48000 Hz
- Quantum: 4096 samples (~85ms latency)
- Min quantum: 2048 samples
- Max quantum: 8192 samples

**When to adjust:**
- If you still hear pops: increase quantum to 8192
- If you need lower latency (direct connection, no KVM): decrease quantum to 1024 or 2048
- For audio production work: decrease to 256-512 (but expect issues with USB/KVM)

**Note:** The current settings are optimized for ThinkPad Thunderbolt 3 Dock → KVM Switch → DisplayPort Monitor → Audio Jack chain. This setup requires larger buffers due to additional USB latency and KVM switch timing jitter.

### `pipewire-pulse.conf.d/99-usb-dock.conf`

PipeWire's PulseAudio compatibility layer configuration.

**Purpose:** Configures buffer sizes for applications that use the PulseAudio API (native Linux apps).

**Deployed to:**
- `~/.config/pipewire/pipewire-pulse.conf.d/99-usb-dock.conf`

**Settings:**
- Minimum quantum/fragment: 4096 samples (85ms)
- Default target length: 8192 samples (170ms)
- Stream latency: 85ms
- Sample rate: 48000 Hz

### `pulse-client.conf`

PulseAudio client configuration file for PipeWire compatibility layer.

**Purpose:** Placeholder file to prevent PulseAudio client errors. Kept minimal because PipeWire's PulseAudio compatibility layer does NOT support most traditional PulseAudio `client.conf` options.

**Deployed to:**
- `~/.config/pulse/client.conf` (system-wide)
- Can be symlinked to `~/.var/app/APP_ID/config/pulse/client.conf` for flatpak apps

**Important:** All actual audio configuration (buffer sizes, sample rates, latency) is done in PipeWire configuration files, not here:
- Use `pipewire.conf.d/99-usb-dock.conf` for core PipeWire settings
- Use `pipewire-pulse.conf.d/99-usb-dock.conf` for PulseAudio compatibility layer settings

**Note:** Options like `default-fragment-size-msec`, `default-buffer-size-msec`, `default-sample-rate`, etc. are **not supported** by PipeWire and will cause warnings if included.

## WirePlumber Configuration

### `../wireplumber/main.lua.d/51-alsa-usb-dock.lua`

WirePlumber rules for ALSA buffer configuration.

**Purpose:** Configures low-level ALSA buffer sizes for all audio devices, with special rules for USB audio.

**Deployed to:**
- `~/.config/wireplumber/main.lua.d/51-alsa-usb-dock.lua`

**Settings:**
- USB-specific period size: 4096 samples (85ms at 48kHz)
- USB-specific period count: 2 periods
- USB-specific headroom: 8192 samples
- USB-specific: batching enabled for better buffering
- Auto-suspend disabled (prevents pops when resuming)
- Fixed 48kHz sample rate
- Channel mapping disabled for stability

**Why this matters:** ALSA is the lowest level before the hardware. These settings keep normal devices at low latency while giving USB audio devices extra buffers for KVM switch stability.

**Important:** Only USB devices get the larger buffers. Increasing buffers for all devices can cause audio to disappear in some applications.

## Applying Changes

The home-manager configuration includes an automatic activation step that restarts PipeWire services after applying changes.

```bash
# Rebuild home-manager (PipeWire will restart automatically)
home-manager switch

# Or if in the dotfiles directory
cd ~/git/dotfiles/src/nix/home-manager
home-manager switch --flake .
```

**Manual restart (if needed):**
```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

## Troubleshooting

### Check current settings
```bash
pw-metadata -n settings | grep quantum
```

### List audio devices
```bash
wpctl status
```

### Check if USB autosuspend is disabled (should be -1)
```bash
cat /sys/module/usbcore/parameters/autosuspend
```

### Check for conflicting manual configurations
The Nix configuration may be overridden by manual config files. Check for these:
```bash
# These should be symlinks to /nix/store, not regular files
ls -la ~/.config/pipewire/pipewire.conf.d/
ls -la ~/.config/wireplumber/main.lua.d/

# If you see regular files (not symlinks), they may be conflicting
# Disable them by renaming to .disabled
```

### Audio popping troubleshooting checklist
If you experience audio popping:

1. **Check for config conflicts** - Ensure no manual configs override Nix
2. **Verify quantum settings** - Should be 4096+ for USB through KVM
3. **Test hardware path**:
   - Try bypassing KVM switch temporarily
   - Try direct dock audio output instead of monitor's audio jack
   - Test with different speakers/cable
4. **Check for electromagnetic interference**:
   - Separate audio and power cables
   - Use shielded cables
   - Move dock away from power supplies
5. **Monitor kernel logs** during playback:
   ```bash
   journalctl -f -k | grep -i "usb\|audio\|xhci"
   ```
