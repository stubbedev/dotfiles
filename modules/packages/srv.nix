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
      # Migration is automatic — see migrateSrvDaemonUnit below.
      systemd.user.services.srv-daemon = {
        Unit = {
          Description = "srv daemon - Docker container network connector";
          Documentation = "https://github.com/stubbedev/srv";
          # No `After = docker.service`: this is a *user* unit and ordering
          # only resolves against other user-manager units, so a dep on the
          # system docker.service is silently ignored. The docker-not-ready
          # race is handled by Restart=on-failure below instead.
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

      # Auto-migrate off any imperatively-installed daemon unit. `srv daemon
      # install` writes a *real* file at this path; home-manager links its own
      # unit there and would abort with "Existing file would be clobbered"
      # (no backupFileExtension is set). Runs before checkLinkTargets so the
      # path is clear when HM links. Only a real file is removed — an existing
      # HM symlink is left untouched, so this is a no-op on already-migrated
      # hosts and on macOS (no systemd user dir, the test just fails).
      home.activation.migrateSrvDaemonUnit = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        _srv_unit="${config.xdg.configHome}/systemd/user/srv-daemon.service"
        if [ -e "$_srv_unit" ] && [ ! -L "$_srv_unit" ]; then
          $DRY_RUN_CMD rm -f $VERBOSE_ARG "$_srv_unit"
        fi
      '';
    };
}
