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
      srvExe = lib.getExe' pkgs.srv "srv";
      peerState = "${config.xdg.stateHome}/srv";
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

      programs.zsh.loginExtra = lib.mkIf onAndroid ''
        () {
          local pidfile=${lib.escapeShellArg "${peerState}/peer.pid"}
          if [[ -r $pidfile ]] && kill -0 "$(<$pidfile)" 2>/dev/null; then
            return
          fi
          mkdir -p ${lib.escapeShellArg peerState}
          ${srvExe} peer run >>${lib.escapeShellArg "${peerState}/peer.log"} 2>&1 &!
          print -r -- $! >$pidfile
        }
      '';
    };
}
