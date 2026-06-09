_: {
  flake.modules.homeManager.packagesSrv =
    {
      pkgs,
      lib,
      config,
      srv,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      srvBin = "${srv.packages.${system}.srv}/bin/srv";
    in
    lib.mkIf config.features.srv {
      home.packages = [
        srv.packages.${system}.srv
        pkgs.mkcert
        # certutil — used by mkcert to install the root CA into Firefox/
        # Chromium NSS databases.
        pkgs.nss.tools
      ];

      # Own the srv watch daemon declaratively instead of via
      # `srv daemon install`. That imperative installer bakes the
      # then-current /nix/store path of the srv binary into the unit's
      # ExecStart; the next srv upgrade or `nix-collect-garbage` deletes
      # that path, leaving the unit crash-looping with status=203/EXEC
      # ("Unable to locate executable"). A dead daemon never connects site
      # containers to the Traefik network, so Traefik falls back to its
      # self-signed default cert for every local site (start.local included)
      # — which on NixOS looks like an untrusted/invalid cert. Pointing
      # ExecStart at the flake-pinned binary tracks the current srv and
      # keeps it a GC root, so it never goes stale.
      #
      # Migration: a previously `srv daemon install`-ed unit leaves a real
      # file at ~/.config/systemd/user/srv-daemon.service that collides with
      # this one — run `srv daemon uninstall` once before the first switch.
      systemd.user.services.srv-daemon = {
        Unit = {
          Description = "srv daemon - Docker container network connector";
          Documentation = "https://github.com/stubbedev/srv";
          After = [ "docker.service" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${srvBin} daemon start --foreground";
          Restart = "on-failure";
          RestartSec = 5;
          # systemd user services start with a minimal PATH and do not
          # inherit the interactive shell's. srv shells out to `docker`, so
          # surface the host's client — /run/current-system on NixOS,
          # /usr/bin on a standalone-HM distro (absent dirs are ignored).
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
            "XDG_CONFIG_HOME=${config.xdg.configHome}"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
