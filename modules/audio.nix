# Audio: PipeWire as the server, WirePlumber as the session manager, and the
# per-device drop-ins this laptop and its dock need.
_: {
  flake.modules.nixos.audio = _: {
    # PipeWire replaces PulseAudio + JACK. The HM half below drops *.conf files
    # into ~/.config/{pipewire,wireplumber}.conf.d/, which both daemons read on
    # either target.
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    # Required by PipeWire for realtime scheduling of audio threads.
    security.rtkit.enable = true;

    # Disable the legacy PulseAudio service NixOS ships by default; PipeWire's
    # pulse shim provides the same socket interface.
    services.pulseaudio.enable = false;
  };

  flake.modules.homeManager.audio =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile =
        lib.genAttrs
          [
            # Realtime scheduling for PipeWire threads (audio, camera, capture).
            "pipewire/pipewire.conf.d/10-realtime-scheduling.conf"
            # Pin clock rate / resampler quality at context level.
            "pipewire/pipewire.conf.d/12-default-clock-rate.conf"
            # WirePlumber ALSA configuration (the .conf format WirePlumber 1.4+ wants).
            "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf"
            "wireplumber/wireplumber.conf.d/51-alsa-usb-dock.conf"
            # Idle timeout for the internal SoundWire sinks (pop on codec resume).
            "wireplumber/wireplumber.conf.d/52-sof-codec-idle.conf"
            "wireplumber/wireplumber.conf.d/60-disable-bt-autoswitch.conf"
          ]
          (path: {
            source = pkgs.stubbe.file "src/audio/${baseNameOf path}";
          });
    };
}
