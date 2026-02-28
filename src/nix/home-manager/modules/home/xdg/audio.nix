_: {
  flake.modules.homeManager.xdgAudio =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
        # PipeWire audio configuration for USB docks with KVM switches
        "pipewire/pipewire.conf.d/99-usb-dock.conf"
        "pipewire/pipewire-pulse.conf.d/99-usb-dock.conf"
        # Low-latency PipeWire configuration for screen sharing and camera
        "pipewire/pipewire.conf.d/10-screenshare-optimize.conf"

        # WirePlumber ALSA configuration (new .conf format for WirePlumber 1.4+)
        "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf"
        "wireplumber/wireplumber.conf.d/51-alsa-usb-dock.conf"
        "wireplumber/wireplumber.conf.d/52-hdmi-dp-buffers.conf"
        "wireplumber/wireplumber.conf.d/60-disable-bt-autoswitch.conf"
      ];
    };
}
