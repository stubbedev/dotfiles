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
    { config, lib, ... }:
    lib.mkIf config.features.desktop {
      xdg.configFile = {
        "pipewire/pipewire.conf.d/10-realtime-scheduling.conf".text = ''
          # Realtime scheduling for PipeWire so screen-share, camera, and audio
          # threads can hold their deadlines without dropouts.
          #
          # An earlier version also set `stream.properties.node.latency = 512/48000`
          # globally to "lower latency for screen capture", but `stream.properties`
          # applies to every stream, not just screen capture. That forced ~10 ms
          # latency on all audio clients (incl. browsers). Per-stream latency is
          # better negotiated by the apps themselves.

          context.modules = [
              {   name = libpipewire-module-rt
                  args = {
                      nice.level   = -11
                      rt.prio      = 88
                      rt.time.soft = -1
                      rt.time.hard = -1
                  }
                  flags = [ ifexists nofail ]
              }
          ]
        '';

        "pipewire/pipewire.conf.d/12-default-clock-rate.conf".text = ''
          # Default PipeWire clock rate and resampler quality.
          # These belong in context.properties, not monitor.alsa.rules.update-props
          # (where they were silently ignored at node level).
          #
          # `default.clock.allowed-rates` lists the rates the graph may switch to
          # when a stream of that native rate connects, avoiding resampling for
          # common content (48 kHz video, 44.1 kHz music).

          context.properties = {
              default.clock.rate          = 48000
              default.clock.allowed-rates = [ 44100 48000 88200 96000 ]
              default.resample.quality    = 4
          }
        '';

        "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf".text = ''
          # HDMI/DisplayPort sinks: never suspend (suspend/resume renegotiates the
          # audio infoframe and pops — see 52-sof-codec-idle.conf for the internal
          # sinks' variant) and larger buffers against initial-playback pops.

          monitor.alsa.rules = [
            {
              matches = [
                {
                  node.name = "~alsa_output.*hdmi*"
                }
                {
                  node.name = "~alsa_output.*HDMI*"
                }
                {
                  node.name = "~alsa_output.*DisplayPort*"
                }
                {
                  # Fallback naming when UCM route names aren't ready at enumeration:
                  # the sof_sdw HDMI PCMs are devices 5-7 (0-4, the speaker/headset
                  # PCMs, are handled by 52-sof-codec-idle.conf). Without this the
                  # HDMI sinks lost never-suspend + the large buffers on such boots.
                  node.name = "~alsa_output.*sof_sdw.HiFi__hw_sofsoundwire_[5-7]__sink"
                }
              ]
              actions = {
                update-props = {
                  # api.alsa.use-acp, api.alsa.period-num and api.alsa.start-delay
                  # used to be set here too: use-acp is a device-level property that
                  # does nothing in a node rule, period-num is not honored at
                  # update-props (see 51-alsa-usb-dock.conf), start-delay = 0 is the
                  # default.
                  session.suspend-timeout-seconds = 0
                  node.pause-on-idle = false
                  # Larger buffers to prevent initial pop when starting playback
                  api.alsa.headroom = 8192
                  api.alsa.period-size = 2048
                }
              }
            }
          ]

          monitor.alsa.properties = {
            alsa.reserve = false
          }
        '';

        "wireplumber/wireplumber.conf.d/51-alsa-usb-dock.conf".text = ''
          # Larger ALSA buffers for USB audio devices (e.g. the Thunderbolt dock)
          # to absorb USB/dock jitter and prevent popping.
          #
          # Match key is `alsa.driver_name`; `api.alsa.card.driver` is not a real
          # property at monitor.alsa.rules time and was being silently skipped.
          #
          # `api.alsa.period-num` is not honored at update-props in WirePlumber 1.4+
          # (live value tracks period-size regardless of what we set), so it's removed
          # rather than misleading future readers. `audio.rate` and `resample.quality`
          # moved to pipewire.conf.d/12-default-clock-rate.conf where they're actually
          # applied (context.properties, not per-node update-props).

          monitor.alsa.rules = [
            {
              matches = [
                {
                  alsa.driver_name = "snd_usb_audio"
                }
              ]
              actions = {
                update-props = {
                  api.alsa.period-size = 4096
                  api.alsa.headroom = 8192
                  api.alsa.disable-batch = false
                  session.suspend-timeout-seconds = 0
                  node.pause-on-idle = false
                  api.alsa.use-chmap = false
                }
              }
            }
          ]
        '';

        "wireplumber/wireplumber.conf.d/52-sof-codec-idle.conf".text = ''
          # Keep the internal SoundWire codec open across short gaps in playback.
          #
          # WirePlumber suspends an idle node after 5s by default. On this ThinkPad
          # that closes the PCM, the SOF controller runtime-suspends 2s later, and the
          # rt1318 amps power down — so the next notification sound arrives with an
          # audible pop as they come back up. That is the pop that a
          # `systemctl --user restart wireplumber` papers over.
          #
          # The USB and HDMI sinks already opt out of suspend entirely (0 = never) in
          # 51-alsa-usb-dock.conf / 50-enable-hdmi-audio.conf. The internal sinks get a
          # timeout instead of 0 because they are the ones that matter on battery: a
          # codec pinned awake keeps the SOF controller out of runtime suspend for the
          # whole session. 10 minutes covers a working day's worth of intermittent
          # audio and still lets the codec sleep once the machine is genuinely idle.
          # Set to 0 if a pop after ten quiet minutes is still one pop too many.

          monitor.alsa.rules = [
            {
              matches = [
                {
                  node.name = "~alsa_output.*sof_sdw.HiFi__Speaker__sink"
                }
                {
                  node.name = "~alsa_output.*sof_sdw.HiFi__Headphones__sink"
                }
                {
                  # Some boots enumerate the card before UCM route names are ready and
                  # the sinks come up as HiFi__hw_sofsoundwire_N__sink (seen in
                  # wireplumber's default-nodes state). Those missed the rules above,
                  # fell back to the 5s default, and popped until a wireplumber
                  # restart re-enumerated with proper names. Devices 0-4 are the
                  # headset/speaker PCMs; 5-7 are HDMI, which must stay on the
                  # never-suspend rule in 50-enable-hdmi-audio.conf.
                  node.name = "~alsa_output.*sof_sdw.HiFi__hw_sofsoundwire_[0-4]__sink"
                }
              ]
              actions = {
                update-props = {
                  session.suspend-timeout-seconds = 600
                }
              }
            }
          ]
        '';

        "wireplumber/wireplumber.conf.d/60-disable-bt-autoswitch.conf".text = ''
          # Disable Bluetooth headset profile autoswitch (keeps A2DP active)

          monitor.bluez.properties = {
            bluez5.autoswitch-profile = false
          }
        '';
      };
    };
}
