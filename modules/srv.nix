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
        # Mirrors srv's own drop-in (internal/traefik/dns.go) byte for byte, so
        # `srv install`/`srv add` see it unchanged and never need sudo here. srv
        # routes .test/.localhost wholesale and every other domain by name; the
        # embedded DNS server is a user service on an unprivileged port.
        script = ''
          src=${domainsFile}
          out=/etc/systemd/resolved.conf.d/srv-local.conf
          mkdir -p /etc/systemd/resolved.conf.d
          # Sorts after srv-local.conf and overrode it (port-less DNS=) -- srv
          # deletes it too, but this unit used to write it.
          rm -f /etc/systemd/resolved.conf.d/srv.conf
          domains="~test ~localhost"
          if [ -r "$src" ]; then
            while IFS= read -r name || [ -n "$name" ]; do
              name=$(printf '%s' "$name" | tr -d '[:space:]')
              [ -n "$name" ] || continue
              case "$name" in \#*) continue ;; esac
              name=''${name#\*.}
              case "$name" in
                test | *.test | localhost | *.localhost) continue ;;
              esac
              domains="$domains ~$name"
            done < "$src"
          fi
          printf '[Resolve]\nDNS=127.0.0.1:15353\nDomains=%s\n' "$domains" > "$out"
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
        # srv's routing is a resolved drop-in, which only applies to clients that
        # ask resolved's stub on 127.0.0.53. Valet on Linux sets
        # DNSStubListener=no in resolved.conf (its dnsmasq wanted :53); with the
        # listener off, resolved writes the upstream servers into
        # stub-resolv.conf as well, so re-pointing /etc/resolv.conf -- what
        # `srv install --yes` does -- changes nothing. A drop-in overrides the
        # main file; srv's own DNS is on :15353, so nothing needs :53 any more.
        resolvedStubListener = lib.mkIf (config.host.platform != "nixos") {
          privileged = true;
          title = "Re-enabling the systemd-resolved stub listener";
          body = ''
            Write /etc/systemd/resolved.conf.d/stub-listener.conf
            (DNSStubListener=yes), restart systemd-resolved, and link
            /etc/resolv.conf to /run/systemd/resolve/stub-resolv.conf, so every
            lookup goes through resolved at 127.0.0.53 and srv's local domains
            resolve locally. Upstream DNS servers are unchanged.
          '';
          preCheck = ''
            stub=/run/systemd/resolve/stub-resolv.conf
            if [ ! -e "$stub" ]; then
              echo "resolved-stub-listener: systemd-resolved not running; skipping."
              exit 0
            fi
            if grep -q '^nameserver 127\.0\.0\.53$' "$stub" \
              && [ "$(readlink /etc/resolv.conf)" = "$stub" ]; then
              exit 0
            fi
          '';
          script = ''
            sudo mkdir -p /etc/systemd/resolved.conf.d
            printf '[Resolve]\nDNSStubListener=yes\n' \
              | sudo tee /etc/systemd/resolved.conf.d/stub-listener.conf >/dev/null
            sudo systemctl restart systemd-resolved.service
            sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
          '';
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
