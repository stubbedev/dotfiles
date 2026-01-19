# PipeWire Configuration

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
- Quantum: 1024 samples (~21ms latency)
- Min quantum: 512 samples
- Max quantum: 2048 samples

**When to adjust:**
- If you still hear pops: increase quantum to 2048
- If you need lower latency (direct connection, no KVM): decrease quantum to 256 or 512
- For audio production work: decrease to 128-256 (but expect issues with USB/KVM)

### `pipewire-pulse.conf.d/99-usb-dock.conf`

PipeWire's PulseAudio compatibility layer configuration.

**Purpose:** Configures buffer sizes for applications that use the PulseAudio API (native Linux apps).

**Deployed to:**
- `~/.config/pipewire/pipewire-pulse.conf.d/99-usb-dock.conf`

**Settings:**
- Minimum quantum/fragment: 1024 samples (21ms)
- Default target length: 2048 samples (42ms)
- Stream latency: 21ms
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
- General ALSA period size: 256 samples (default, works for most devices)
- General ALSA: batching disabled for low latency
- USB-specific period size: 1024 samples (4x larger for stability)
- USB-specific headroom: 2048 samples
- USB-specific: batching enabled for better buffering
- Auto-suspend disabled (prevents pops when resuming)
- Fixed 48kHz sample rate

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
