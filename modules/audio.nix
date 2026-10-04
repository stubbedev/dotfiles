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
    {
      config,
      lib,
      ...
    }:
    lib.mkIf config.features.desktop {
      # The module symlinks each config dir whole; the live ones still hold
      # the previous generation's individually-managed drop-ins, so clobber
      # them.
      xdg.configFile."pipewire".force = true;
      xdg.configFile."wireplumber".force = true;

      # HM's pipewire module deploys these as SPA-JSON drop-ins under
      # pipewire.conf.d/ and wireplumber.conf.d/. Keys are flat and contain
      # dots ("monitor.alsa.rules"), so they must stay quoted: unquoted nix
      # attribute paths would nest them and the daemon would ignore the
      # fragment.
      services.pipewire = {
        enable = true;

        configs = {
          "10-realtime-scheduling" = {
            "context.modules" = [
              {
                name = "libpipewire-module-rt";
                args = {
                  "nice.level" = -11;
                  "rt.prio" = 88;
                  "rt.time.soft" = -1;
                  "rt.time.hard" = -1;
                };
                flags = [
                  "ifexists"
                  "nofail"
                ];
              }
            ];
          };

          "12-default-clock-rate" = {
            "context.properties" = {
              "default.clock.rate" = 48000;
              "default.clock.allowed-rates" = [
                44100
                48000
                88200
                96000
              ];
              "default.resample.quality" = 4;
            };
          };
        };

        wireplumber = {
          enable = true;

          configs = {
            "50-enable-hdmi-audio" = {
              "monitor.alsa.rules" = [
                {
                  matches = [
                    { "node.name" = "~alsa_output.*hdmi*"; }
                    { "node.name" = "~alsa_output.*HDMI*"; }
                    { "node.name" = "~alsa_output.*DisplayPort*"; }
                    { "node.name" = "~alsa_output.*sof_sdw.HiFi__hw_sofsoundwire_[5-7]__sink"; }
                  ];
                  actions.update-props = {
                    "session.suspend-timeout-seconds" = 0;
                    "node.pause-on-idle" = false;
                    "api.alsa.headroom" = 8192;
                    "api.alsa.period-size" = 2048;
                  };
                }
              ];
              "monitor.alsa.properties" = {
                "alsa.reserve" = false;
              };
            };

            "51-alsa-usb-dock" = {
              "monitor.alsa.rules" = [
                {
                  matches = [ { "alsa.driver_name" = "snd_usb_audio"; } ];
                  actions.update-props = {
                    "api.alsa.period-size" = 4096;
                    "api.alsa.headroom" = 8192;
                    "api.alsa.disable-batch" = false;
                    "session.suspend-timeout-seconds" = 0;
                    "node.pause-on-idle" = false;
                    "api.alsa.use-chmap" = false;
                  };
                }
              ];
            };

            "52-sof-codec-idle" = {
              "monitor.alsa.rules" = [
                {
                  matches = [
                    { "node.name" = "~alsa_output.*sof_sdw.HiFi__Speaker__sink"; }
                    { "node.name" = "~alsa_output.*sof_sdw.HiFi__Headphones__sink"; }
                    { "node.name" = "~alsa_output.*sof_sdw.HiFi__hw_sofsoundwire_[0-4]__sink"; }
                  ];
                  actions.update-props = {
                    "session.suspend-timeout-seconds" = 600;
                  };
                }
              ];
            };

            "60-disable-bt-autoswitch" = {
              "monitor.bluez.properties" = {
                "bluez5.autoswitch-profile" = false;
              };
            };
          };
        };
      };
    };
}
