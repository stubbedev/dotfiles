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

      systemd.user.services =
        if onAndroid then
          {
            # The phone runs no srv daemon, only its peer discovery.
            srv-peer = {
              Unit = {
                Description = "srv LAN peer discovery";
                X-Restart-Triggers = [ "${srvConfig}" ];
              };
              Service = {
                ExecStart = "${lib.getExe' pkgs.srv "srv"} peer run";
                Restart = "on-failure";
              };
              Install.WantedBy = [ "default.target" ];
            };
          }
        else
          { srv-daemon.Unit.X-Restart-Triggers = [ "${srvConfig}" ]; };

      home.packages = lib.mkIf onAndroid [ pkgs.srv ];
    };
}
