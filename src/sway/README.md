# Sway Configuration

This is a complete Sway configuration converted from your Hyprland setup. It includes all the same features and functionality.

## Files Structure

- `config` - Main Sway configuration file
- `env` - Environment variables and session setup
- `variables` - Color theme variables (Catppuccin Mocha)
- `theme` - Window border colors and appearance
- `keybinds` - All keyboard shortcuts and mouse bindings
- `input` - Keyboard and touchpad configuration
- `output` - Monitor/display configuration
- `window_rules` - Window-specific rules and behavior
- `startup` - Programs to start with Sway
- `swaylock.conf` - Screen lock appearance configuration
- `swayidle.sh` - Idle management script
- `scripts/lid-close-open.sh` - Laptop lid event handler

## Key Features Converted

### From Hyprland → Sway equivalent:
- **hyprlock** → swaylock (with custom config)
- **hypridle** → swayidle (with script)
- **hyprpaper** → swaybg (in startup)
- **hyprsunset** → wlsunset (in startup)
- **hyprshot** → grimshot (screenshot tool)
- **hyprctl** → swaymsg (for scripts)

### Keybindings:
- Super+Return: Terminal
- Super+Space: Application launcher (rofi)
- Super+Shift+Q: Kill window
- Super+F: Fullscreen
- Super+T: Toggle floating
- Super+Escape: Lock screen
- Super+1-0: Switch workspaces
- Super+Shift+1-0: Move to workspace
- Super+R: Resize mode
- Media keys: Volume and playback control

### Features:
- Catppuccin Mocha color theme
- No gaps, no animations (matching your Hyprland setup)
- Multi-monitor support with scaling
- Touchpad configuration
- Lid event handling
- Clipboard history with cliphist
- Waybar integration
- System tray applications

## Installation

1. Install required packages:
   ```bash
   # Arch Linux
   sudo pacman -S sway swaylock swayidle swaybg wlsunset grimshot

   # Ubuntu/Debian  
   sudo apt install sway swaylock swayidle swaybg wlsunset grimshot

   # Fedora
   sudo dnf install sway swaylock swayidle swaybg wlsunset grimshot
   ```

2. Copy configuration files:
   ```bash
   cp -r src/sway ~/.config/
   ```

3. Start Sway:
   ```bash
   sway
   ```

## Dependencies

The configuration assumes these programs are installed:
- rofi (application launcher)
- waybar (status bar)
- cliphist (clipboard manager)
- playerctl (media control)
- amixer (volume control)
- alacritty/ghostty/kitty (terminal)
- blueman-applet, nm-applet (system tray)
- swaync (notifications)
- jq (for scripts)

All the same programs you use with Hyprland should work with this Sway setup.