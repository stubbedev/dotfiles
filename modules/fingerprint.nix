{
  flake.modules.nixos.fingerprint =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      lidClosed = pkgs.writeShellScript "lid-closed" ''
        set -euo pipefail
        state=$(${config.systemd.package}/bin/busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed)
        [ "$state" = "b true" ]
      '';
      pamExec = "${config.security.pam.package}/lib/security/pam_exec.so";
    in
    {
      options.security.pam.services = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              rules.auth.fprintd-lid-closed = {
                enable = config.rules.auth ? fprintd && config.rules.auth.fprintd.enable;
                order = (config.rules.auth.fprintd.order or 1) - 1;
                control = "[success=1 default=ignore]";
                modulePath = pamExec;
                args = [
                  "quiet"
                  "${lidClosed}"
                ];
              };
            }
          )
        );
      };
    };
}
