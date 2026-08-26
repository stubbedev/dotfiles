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
        # Realtime scheduling for PipeWire threads (audio, camera, capture)
        "pipewire/pipewire.conf.d/10-realtime-scheduling.conf"
        # Pin clock rate / resampler quality at context level
        "pipewire/pipewire.conf.d/12-default-clock-rate.conf"

        # WirePlumber ALSA configuration (new .conf format for WirePlumber 1.4+)
        "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf"
        "wireplumber/wireplumber.conf.d/51-alsa-usb-dock.conf"
        # Idle timeout for the internal SoundWire sinks (pop on codec resume)
        "wireplumber/wireplumber.conf.d/52-sof-codec-idle.conf"
        "wireplumber/wireplumber.conf.d/60-disable-bt-autoswitch.conf"
      ];
    };
}
