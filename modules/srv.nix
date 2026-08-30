# srv — the local-site server: Traefik + per-site containers, reachable at
# https://<name>.local with mkcert-signed certificates.
#
# The certificate trust story is why this file has four blocks. srv generates
# per-site certs signed by the mkcert root CA, and nothing trusts that CA until
# it is installed:
#   * NixOS system store  → security.pki.certificateFiles (nixos half)
#   * NixOS browser NSS   → an unprivileged `mkcert -install` with
#                           TRUST_STORES=nss (mkcertNss below), because
#                           security.pki only covers the system store
#   * non-NixOS both      → one privileged `mkcert -install` (mkcertTrust),
#                           which does the system store AND the NSS databases
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
        # certutil — mkcert uses it to install the root CA into the
        # Firefox/Chromium NSS databases.
        pkgs.nss.tools
      ];

      # builtins.path imports the cert into the store so nss-cacert can read it
      # from inside the build sandbox; a raw "/home/…" string would resolve at
      # eval time but be unreadable at build time.
      security.pki.certificateFiles = lib.optional (builtins.pathExists rootCA) (
        builtins.path {
          path = rootCA;
          name = "mkcert-rootCA.pem";
        }
      );

      # Hand DNS to systemd-resolved so split-DNS layers cleanly on top
      # of whatever per-link nameservers NetworkManager negotiates
      # (corp, VPN, ISP). srv_dns answers only the names srv has
      # registered; everything else stays on the link's upstream.
      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";

      # Whenever srv writes its domain list, regenerate the resolved
      # drop-in so adds/removes take effect without a nix-rebuild. Also
      # runs at boot so already-registered sites work after a reboot.
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
          # Reload only if resolved is up — on boot the .service ordering
          # handles this, but during an early hm-switch resolved may not
          # yet be active and we don't want a transient failure to mark
          # the unit failed; the drop-in is on disk either way.
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
      # Migration off the imperative unit is automatic — see the `force`
      # below.
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
          ExecStart = "${lib.getExe' srvPkg "srv"} daemon start --foreground";
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
      # install` writes a *real* file at this path, which home-manager would
      # refuse to replace ("Existing file would be clobbered" -- no
      # backupFileExtension is set). `force` claims the path instead.
      #
      # This merges onto the unit home-manager's systemd module already
      # generates: it renders every unit through `xdg.configFile` under
      # exactly this name, setting `source`, and this adds `force`. Linux
      # only -- on darwin that module is disabled, so there is no entry to
      # attach to and defining one alone would be a file with no source.
      xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        "systemd/user/srv-daemon.service".force = true;
      };

      stubbe.setup = {
        # Non-NixOS: `mkcert -install` trusts the CA in BOTH the system store
        # and the browser NSS databases.
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
          # Skip until srv/mkcert has generated the root CA — the next switch
          # retries once it exists.
          preCheck = ''
            if [ ! -f "${rootCA}" ]; then
              echo "mkcert-trust: root CA not generated yet (run 'srv install'); skipping."
              exit 0
            fi
          '';
          # mkcert needs certutil (nss.tools) on PATH to reach the NSS stores;
          # without it the system store is still updated but browsers are not.
          # mkcert invokes sudo itself for the system store.
          script = ''
            export PATH="${pkgs.nss.tools}/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
            ${lib.getExe pkgs.mkcert} -install
          '';
          # Re-run when the CA appears or disappears (regenerated, fresh OS).
          stateInputs = [ rootCA ];
        };

        # NixOS: security.pki above replaces only the SYSTEM-store half, so
        # nothing seeds NSS and https://start.local validates with curl but is
        # still rejected by Firefox/Chromium. This closes that gap. mkcert's NSS
        # installer is unprivileged (the NSS dbs are user-owned), so no sudo —
        # and TRUST_STORES=nss keeps it from trying to sudo into the system
        # store that security.pki already owns.
        mkcertNss = lib.mkIf (config.host.platform == "nixos") {
          script = ''
            if [ -f "${rootCA}" ]; then
              # certutil (nss.tools) must be on PATH or mkcert silently skips
              # the NSS stores.
              export PATH="${pkgs.nss.tools}/bin:$PATH"
              export TRUST_STORES=nss
              # Idempotent — runs every switch to catch new browser profiles or
              # a reset NSS db. Its "CA is (already) installed" chatter goes to
              # /dev/null; stderr still surfaces real failures.
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
