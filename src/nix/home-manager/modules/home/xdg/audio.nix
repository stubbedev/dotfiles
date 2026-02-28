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
        # Low-latency PipeWire configuration for screen sharing and camera
        "pipewire/pipewire.conf.d/10-screenshare-optimize.conf"
        # Prevent initial pop when starting audio playback
        "pipewire/pipewire.conf.d/11-prevent-startup-pop.conf"

        # WirePlumber ALSA configuration (new .conf format for WirePlumber 1.4+)
        "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf"
        "wireplumber/wireplumber.conf.d/51-alsa-usb-dock.conf"
        "wireplumber/wireplumber.conf.d/60-disable-bt-autoswitch.conf"
      ];
    };
}
