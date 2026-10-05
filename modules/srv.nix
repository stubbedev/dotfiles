# srv fronts local sites (Traefik + vendored mkcert + embedded DNS on
# 127.0.0.1:15353). Everything environmental — CA generation, the
# systemd-resolved drop-in, the stub listener — is `srv install`'s job
# now (one sudo prompt, `srv doctor` verifies); this module ships what srv
# cannot do for itself: the committed rootCA as the build-time trust seed,
# and the NSS databases its vendored mkcert does not scan.
{ inputs, ... }:
{
  flake.modules.nixos.srv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.srv {
      # certutil, so srv's vendored mkcert can trust the local CA in the
      # browsers' NSS store (security.pki below only covers the system store).
      environment.systemPackages = [ pkgs.nss.tools ];

      # Flake evals are restricted to the flake tree, so a runtime-generated
      # CA under $HOME is invisible here (builtins.pathExists silently returns
      # false). The cert is committed instead and the user's CAROOT below is
      # pinned to the same file, leaving `srv install` to mint only leaves.
      security.pki.certificateFiles = [ ../certs/mkcert-rootCA.pem ];

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
      rootCA = ../certs/mkcert-rootCA.pem;
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

      # Pin the CA cert to the committed copy, so the system store and every
      # NSS database always see the same CA that srv signs with. force, because
      # machines provisioned before this still hold mkcert's real file there.
      xdg.dataFile."mkcert/rootCA.pem" = {
        source = rootCA;
        force = true;
      };

      # srv's vendored mkcert only scans the legacy NSS locations (~/.mozilla,
      # ~/.pki): HM's Firefox profiles live under ~/.config/mozilla and current
      # Chrome keeps its user DB at ~/.local/share/pki. Seed those directly —
      # user-owned databases, idempotent, no sudo. A stray `sudo` browser run
      # can leave a profile's NSS files root-owned: unreadable to us and to the
      # browser alike, so nothing is lost by moving them aside (the dir is
      # ours) and starting a fresh DB. Best-effort: never blocks activation.
      stubbe.setup.nssTrust = {
        script = ''
          certutil=${lib.getExe' pkgs.nss.tools "certutil"}
          for db in \
            "$HOME"/.config/mozilla/firefox/*/cert9.db \
            "$HOME"/.local/share/pki/nssdb/cert9.db \
            "$HOME"/.pki/nssdb/cert9.db; do
            [ -f "$db" ] || continue
            dir=''${db%cert9.db}
            if [ ! -O "$db" ] || [ ! -w "$db" ]; then
              for f in cert9.db key4.db pkcs11.txt; do
                if [ -e "$dir$f" ]; then mv -f "$dir$f" "$dir$f.unowned-bak"; fi
              done
              "$certutil" -N --empty-password -d "sql:$dir" >/dev/null 2>&1 || continue
            fi
            "$certutil" -A -d "sql:$dir" -i ${rootCA} \
              -n "mkcert development CA" -t "C,," >/dev/null 2>&1 || true
          done
        '';
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
