_: {
  flake.modules.nixos.peers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.peers {
      networking.firewall.allowedUDPPorts = [ pkgs.stubbe.peerPort ];
    };

  flake.modules.homeManager.peers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      onAndroid = config.host.platform == "android";
      srvConfig = pkgs.writeText "srv-config.yml" ''
        peer_name: ${config.host.flakeAttr}
      '';
    in
    lib.mkIf config.features.peers {
      assertions = [
        {
          assertion = onAndroid || config.features.srv;
          message = "features.peers runs inside the srv daemon on this host; enable features.srv too.";
        }
      ];

      xdg.configFile."srv/config.yml" = {
        source = srvConfig;
        force = true;
      };

      systemd.user.services.srv-daemon.Unit.X-Restart-Triggers = lib.mkIf (!onAndroid) [ "${srvConfig}" ];

      home.packages = lib.mkIf onAndroid [ pkgs.srv ];

      stubbe.androidDaemons = lib.mkIf onAndroid {
        srv-peer = "${lib.getExe' pkgs.srv "srv"} peer run";
      };
    };
}
