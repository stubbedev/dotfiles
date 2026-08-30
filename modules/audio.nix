_: {
  flake.modules.nixos.audio = _: {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    security.rtkit.enable = true;

    services.pulseaudio.enable = false;
  };

  flake.modules.homeManager.audio =
    { config, lib, ... }:
    lib.mkIf config.features.desktop {
      xdg.configFile = {
        "pipewire/pipewire.conf.d/10-realtime-scheduling.conf".text = ''

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

          context.properties = {
              default.clock.rate          = 48000
              default.clock.allowed-rates = [ 44100 48000 88200 96000 ]
              default.resample.quality    = 4
          }
        '';

        "wireplumber/wireplumber.conf.d/50-enable-hdmi-audio.conf".text = ''

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
                  node.name = "~alsa_output.*sof_sdw.HiFi__hw_sofsoundwire_[5-7]__sink"
                }
              ]
              actions = {
                update-props = {
                  session.suspend-timeout-seconds = 0
                  node.pause-on-idle = false
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

          monitor.bluez.properties = {
            bluez5.autoswitch-profile = false
          }
        '';
      };
    };
}
