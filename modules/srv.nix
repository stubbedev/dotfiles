# srv fronts local sites (Traefik + vendored mkcert + embedded DNS on
# 127.0.0.1:15353). Everything environmental — CA generation and trust,
# the systemd-resolved drop-in, the stub listener — is `srv install`'s job
# now (one sudo prompt, `srv doctor` verifies); this module only ships the
# bits srv cannot do for itself.
{ inputs, ... }:
{
  flake.modules.nixos.srv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      userHome = config.users.users.${config.host.primaryUser}.home;
      rootCA = "${userHome}/.local/share/mkcert/rootCA.pem";
    in
    lib.mkIf config.stubbe.userFeatures.srv {
      # certutil, so srv's vendored mkcert can trust the local CA in the
      # browsers' NSS store (security.pki below only covers the system store).
      environment.systemPackages = [ pkgs.nss.tools ];

      # builtins.path so the build sandbox can read it: a raw "/home/..." string
      # resolves at eval time but is unreadable at build time. Seeded on the
      # rebuild after `srv install` first generates the CA.
      security.pki.certificateFiles = lib.optional (builtins.pathExists rootCA) (
        builtins.path {
          path = rootCA;
          name = "mkcert-rootCA.pem";
        }
      );

      # srv's DNS registers via a systemd-resolved drop-in; lookups must reach
      # resolved's stub (127.0.0.53), so NM may not bypass it.
      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";
    };

  flake.modules.homeManager.srv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      srvPkg = inputs.srv.packages.${pkgs.stdenv.hostPlatform.system}.srv;
    in
    lib.mkIf config.features.srv {
      home.packages = [
        srvPkg
        pkgs.nss.tools
      ];

      # Declarative, not `srv daemon install`: that bakes a then-current store
      # path into ExecStart, which the next upgrade or GC deletes, leaving the
      # unit at status=203/EXEC.
      systemd.user.services.srv-daemon = {
        Unit = {
          Description = "srv daemon - Docker container network connector";
          Documentation = "https://github.com/stubbedev/srv";
          # A user unit cannot order against system docker.service -- the dep is
          # silently ignored -- so Restart=on-failure handles that race.
        };
        Service = {
          Type = "simple";
          ExecStart = "${lib.getExe' srvPkg "srv"} daemon start --foreground";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
            "XDG_CONFIG_HOME=${config.xdg.configHome}"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };

      # Auto-migrate off any imperatively-installed daemon unit. `srv daemon
      # install` writes a *real* file at this path, which home-manager would
      # refuse to replace ("Existing file would be clobbered") — this force
      # flag merges onto the unit HM's systemd module already generates.
      xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        "systemd/user/srv-daemon.service".force = true;
      };
    };
}
