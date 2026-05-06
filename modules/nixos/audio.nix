_: {
  flake.modules.nixos.audio =
    { ... }:
    {
      # PipeWire replaces PulseAudio + JACK. WirePlumber is the session manager.
      # The HM-side modules/home/xdg/audio.nix drops drop-in *.conf files into
      # ~/.config/{pipewire,wireplumber}.conf.d/, which both daemons read.
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        wireplumber.enable = true;
      };

      # Required by PipeWire for realtime scheduling of audio threads.
      security.rtkit.enable = true;

      # Disable the legacy PulseAudio service that ships with NixOS by default;
      # PipeWire's pulse shim provides the same socket interface.
      services.pulseaudio.enable = false;
    };
}
