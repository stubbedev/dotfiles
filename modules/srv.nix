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
      domainsFile = "${userHome}/.config/srv/traefik/local-domains.txt";
      rootCA = "${userHome}/.local/share/mkcert/rootCA.pem";
    in
    lib.mkIf config.stubbe.userFeatures.srv {
      environment.systemPackages = [
        pkgs.mkcert
        pkgs.nss.tools
      ];

      # builtins.path so the build sandbox can read it: a raw "/home/..." string
      # resolves at eval time but is unreadable at build time.
      security.pki.certificateFiles = lib.optional (builtins.pathExists rootCA) (
        builtins.path {
          path = rootCA;
          name = "mkcert-rootCA.pem";
        }
      );

      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";

      systemd.paths.srv-resolved-sync = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = domainsFile;
          Unit = "srv-resolved-sync.service";
        };
      };

      systemd.services.srv-resolved-sync = {
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-resolved.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          src=${domainsFile}
          out=/etc/systemd/resolved.conf.d/srv.conf
          mkdir -p /etc/systemd/resolved.conf.d
          domains=""
          if [ -r "$src" ]; then
            while IFS= read -r name || [ -n "$name" ]; do
              [ -n "$name" ] || continue
              case "$name" in \#*) continue ;; esac
              domains="$domains ~$name"
            done < "$src"
          fi
          if [ -n "$domains" ]; then
            printf '[Resolve]\nDNS=127.0.0.1\nDomains=%s\n' "$domains" > "$out"
          else
            rm -f "$out"
          fi
          if systemctl is-active --quiet systemd-resolved.service; then
            systemctl reload systemd-resolved.service || true
          fi
        '';
      };
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
      rootCA = "${config.home.homeDirectory}/.local/share/mkcert/rootCA.pem";
    in
    lib.mkIf config.features.srv {
      home.packages = [
        srvPkg
        pkgs.mkcert
        pkgs.nss.tools
      ];

      # Declarative, not `srv daemon install`: that bakes a then-current store
      # path into ExecStart, which the next upgrade or GC deletes, leaving the
      # unit at status=203/EXEC. A dead daemon leaves Traefik serving its
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
      # refuse to replace ("Existing file would be clobbered" -- no
      # This merges onto the unit home-manager's systemd module already
      # generates: it renders every unit through `xdg.configFile` under
      # exactly this name, setting `source`, and this adds `force`. Linux
      xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        "systemd/user/srv-daemon.service".force = true;
      };

      stubbe.setup = {
        mkcertTrust = {
          privileged = true;
          title = "Installing the mkcert root CA into the system & browser trust stores";
          body = ''
            Run `mkcert -install` to trust the mkcert development root CA
            (${rootCA}). This adds it to the system trust store
            (/usr/local/share/ca-certificates, via update-ca-certificates) and
            the browser NSS databases, so srv-served sites like
            https://start.local validate instead of failing with "unable to
            get local issuer certificate".
          '';
          preCheck = ''
            if [ ! -f "${rootCA}" ]; then
              echo "mkcert-trust: root CA not generated yet (run 'srv install'); skipping."
              exit 0
            fi
          '';
          script = ''
            export PATH="${pkgs.nss.tools}/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
            ${lib.getExe pkgs.mkcert} -install
          '';
          stateInputs = [ rootCA ];
        };

        # security.pki seeds only the system store, so without this a local site
        # validates with curl but is rejected by Firefox/Chromium. TRUST_STORES=nss
        # keeps mkcert from sudo-ing into the store security.pki already owns.
        mkcertNss = lib.mkIf (config.host.platform == "nixos") {
          script = ''
            if [ -f "${rootCA}" ]; then
              export PATH="${pkgs.nss.tools}/bin:$PATH"
              export TRUST_STORES=nss
              ${lib.getExe pkgs.mkcert} -install >/dev/null \
                || echo "mkcert-nss: 'mkcert -install' failed; browsers may not trust local certs." >&2
            else
              echo "mkcert-nss: root CA not generated yet (run 'srv install'); skipping." >&2
            fi
          '';
        };
      };
    };
}
