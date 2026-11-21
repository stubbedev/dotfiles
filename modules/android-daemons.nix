_: {
  flake.modules.homeManager.android-daemons =
    {
      config,
      lib,
      ...
    }:
    let
      state = "${config.xdg.stateHome}/android-daemons";
      daemons = config.stubbe.androidDaemons;
      start =
        name: command:
        let
          pidfile = lib.escapeShellArg "${state}/${name}.pid";
        in
        ''
          if ! { [[ -r ${pidfile} ]] && kill -0 "$(<${pidfile})" 2>/dev/null; }; then
            ${command} >>${lib.escapeShellArg "${state}/${name}.log"} 2>&1 &!
            print -r -- $! >${pidfile}
          fi
        '';
    in
    {
      options.stubbe.androidDaemons = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Long-running processes for the phone, which has no init system: each
          value is a foreground command a login shell starts unless its last
          instance is still alive, logging to
          `$XDG_STATE_HOME/android-daemons/<name>.log`. Starting any of them
          also takes the Termux wake lock, so Android does not suspend them
          with the app in the background.
        '';
      };

      config = lib.mkIf (daemons != { }) {
        assertions = [
          {
            assertion = config.host.platform == "android";
            message = "stubbe.androidDaemons is for the phone; NixOS hosts run services under systemd.";
          }
        ];

        programs.zsh.loginExtra = ''
          mkdir -p ${lib.escapeShellArg state}
          termux-wake-lock
          ${lib.concatStrings (lib.mapAttrsToList start daemons)}
        '';
      };
    };
}
