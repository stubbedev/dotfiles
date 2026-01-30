{ ... }:
{
  flake.modules.homeManager.xdgAudio = { homeLib, lib, config, ... }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
      # PipeWire audio configuration for USB docks with KVM switches
      "pipewire/pipewire.conf.d/99-usb-dock.conf"
      "pipewire/pipewire-pulse.conf.d/99-usb-dock.conf"
      # Low-latency PipeWire configuration for screen sharing and camera
      "pipewire/pipewire.conf.d/10-screenshare-optimize.conf"

      # WirePlumber ALSA configuration for USB dock stability
      "wireplumber/main.lua.d/51-alsa-usb-dock.lua"

      # WirePlumber configuration to enable HDMI/DisplayPort audio
      "wireplumber/main.lua.d/50-enable-hdmi-audio.lua"

      # WirePlumber configuration to stop Bluetooth auto profile switching
      "wireplumber/main.lua.d/60-disable-bt-autoswitch.lua"
      ];
    };
}
