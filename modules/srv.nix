# srv fronts local sites (Traefik + vendored mkcert + embedded DNS on
# 127.0.0.1:15353). `srv install` sets up the host once (one sudo prompt,
# `srv doctor` verifies); this module ships what makes a machine's srv
# reproducible: the shared CA (committed cert, sops-held key), the proxies
# and redirects below, reconciled on every switch, and on NixOS the
# systemd-resolved drop-in srv would otherwise sudo-write into /etc.
{
  config,
  inputs,
  lib,
  ...
}:
let
  proxies = {
    kontainer-test = {
      domain = "kontainer.test";
      port = 8010;
      wildcard = true;
      routes = [
        {
          id = "media-videos";
          path-regex = "^/videos/([^/]+)/(.+)$";
          rewrite = "/abs/videos/\${1}/\${2}";
          url = "http://127.0.0.1:9080";
          preserve-host = false;
        }
        {
          id = "media-cdn-video-stream";
          path-regex = "^/cdn-video-stream/([^/]+)/([^/]+)/(.+)$";
          rewrite = "/\${1}/videos/\${2}/\${3}";
          url = "http://127.0.0.1:9080";
          preserve-host = false;
        }
      ];
    };
    kontainer-com = {
      domain = "kontainer.com";
      port = 3001;
      fallback = "https://kontainer.com";
    };
    k8s-local = {
      domain = "k8s.local";
      port = 8443;
      routes = [
        {
          id = "root";
          path = "/";
          url = "https://192.168.205.91:8443";
          insecure-skip-verify = true;
          preserve-host = false;
          priority = 1000;
        }
      ];
    };
    k8s-grafana-local = {
      domain = "k8s-grafana.local";
      port = 8068;
      routes = [
        {
          id = "root";
          path = "/";
          url = "http://192.168.205.91:8068";
        }
      ];
    };
  };

  redirects = {
    jira-konform-com = {
      domain = "jira.konform.com";
      to = "https://jira.kontainer.com";
    };
  };

  resolvedRouting =
    let
      routingTLDs = [
        "test"
        "localhost"
      ];
      underRoutingTLD =
        domain: lib.any (tld: domain == tld || lib.hasSuffix ".${tld}" domain) routingTLDs;
      domains = lib.sort lib.lessThan (
        lib.filter (domain: !underRoutingTLD domain) (
          lib.unique (
            map (resource: resource.domain) (lib.attrValues proxies ++ lib.attrValues redirects)
            ++ [
              config.stubbe.lib.newtabDomain
              "traefik.local"
            ]
          )
        )
      );
    in
    ''
      [Resolve]
      DNS=127.0.0.1:15353
      Domains=${lib.concatMapStringsSep " " (domain: "~${domain}") (routingTLDs ++ domains)}
      DNSStubListener=yes
    '';
in
{
  flake.modules.nixos.srv =
    { config, lib, ... }:
    lib.mkIf config.stubbe.userFeatures.srv {
      # Flake evals are restricted to the flake tree, so a runtime-generated
      # CA under $HOME is invisible here (builtins.pathExists silently returns
      # false). The cert is committed instead and the user's CAROOT below is
      # pinned to the same file, leaving `srv install` to mint only leaves.
      security.pki.certificateFiles = [ ../certs/mkcert-rootCA.pem ];

      # srv's DNS registers via a systemd-resolved drop-in; lookups must reach
      # resolved's stub (127.0.0.53), so NM may not bypass it.
      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";

      environment.etc."systemd/resolved.conf.d/srv-local.conf".text = resolvedRouting;
      systemd.services.systemd-resolved.restartTriggers = [ resolvedRouting ];
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
      srvExe = lib.getExe' srvPkg "srv";
      rootCA = ../certs/mkcert-rootCA.pem;
      caNickname = "srv CA ${builtins.substring 0 12 (builtins.hashFile "sha256" rootCA)}";
      legacyCaNickname = "mkcert development CA";

      flags = lib.cli.toCommandLine (option: {
        option = "--${option}";
        sep = "=";
        explicitBool = true;
      });

      resources =
        lib.mapAttrsToList (name: proxy: {
          kind = "proxy";
          inherit name;
          commands = [
            (
              [
                "proxy"
                "add"
                "--name=${name}"
              ]
              ++ flags (lib.removeAttrs proxy [ "routes" ])
            )
          ]
          ++ map (
            route:
            [
              "route"
              "add"
              name
            ]
            ++ flags route
          ) (proxy.routes or [ ]);
        }) proxies
        ++ lib.mapAttrsToList (name: redirect: {
          kind = "redirect";
          inherit name;
          commands = [
            (
              [
                "redirect"
                "add"
                "--name=${name}"
              ]
              ++ flags redirect
            )
          ];
        }) redirects;

      stampOf = resource: "${resource.kind}-${resource.name}";

      srvReconcile = pkgs.stubbe.bashApp {
        name = "srv-reconcile";
        runtimeInputs = [
          srvPkg
          pkgs.jq
        ];
        text = ''
          state=${lib.escapeShellArg "${config.xdg.stateHome}/stubbe/srv"}
          mkdir -p "$state"

          present() {
            srv "$1" list --format json | jq -e --arg name "$2" 'any(.[]; .name == $name)' >/dev/null
          }

          applied() {
            [ -f "$state/$1" ] && [ "$(<"$state/$1")" = "$2" ]
          }

          ${lib.concatMapStrings (
            resource:
            let
              stamp = stampOf resource;
              hash = builtins.hashString "sha256" (builtins.toJSON resource.commands);
            in
            ''
              if ! applied ${stamp} ${hash}; then
                echo "srv: applying ${resource.kind} ${resource.name}"
                if present ${resource.kind} ${resource.name}; then
                  srv ${resource.kind} remove ${resource.name} </dev/null >/dev/null
                fi
                ${lib.concatMapStringsSep "\n  " (
                  command: "srv ${lib.escapeShellArgs command} </dev/null >/dev/null"
                ) resource.commands}
                printf '%s' ${hash} >"$state/${stamp}"
              fi
            ''
          ) resources}

          declared=(${lib.escapeShellArgs (map stampOf resources)})
          for stampFile in "$state"/*; do
            [ -e "$stampFile" ] || continue
            stamp=''${stampFile##*/}
            for keep in "''${declared[@]}"; do
              [ "$stamp" = "$keep" ] && continue 2
            done
            kind=''${stamp%%-*}
            name=''${stamp#*-}
            echo "srv: removing undeclared $kind $name"
            if present "$kind" "$name"; then
              srv "$kind" remove "$name" </dev/null >/dev/null
            fi
            rm "$stampFile"
          done
        '';
      };
    in
    lib.mkIf config.features.srv {
      # certutil, so srv's vendored mkcert can trust the local CA in the
      # browsers' NSS store (the system store only covers system TLS).
      home.packages = [
        srvPkg
        pkgs.nss.tools
      ];

      stubbe.zshCompletions._srv = "${srvExe} completion zsh";

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
          ExecStart = "${srvExe} daemon start --foreground";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "PATH=${config.stubbe.paths.hostPath}"
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

      sops.secrets.mkcert-rootCA-key = pkgs.stubbe.secret {
        name = "mkcert-rootCA-key";
        path = "${config.xdg.dataHome}/mkcert/rootCA-key.pem";
      };

      # srv's vendored mkcert only scans the legacy NSS locations (~/.mozilla,
      # ~/.pki): HM's Firefox profiles live under ~/.config/mozilla and current
      # Chrome keeps its user DB at ~/.local/share/pki. Seed those directly —
      # user-owned databases, idempotent, no sudo. A stray `sudo` browser run
      # can leave a profile's NSS files root-owned: unreadable to us and to the
      # browser alike, so nothing is lost by moving them aside (the dir is
      # ours) and starting a fresh DB. Best-effort: a failure is reported but
      # never blocks activation.
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
              if ! "$certutil" -N --empty-password -d "sql:$dir"; then
                echo "nssTrust: could not create an NSS database in $dir" >&2
                continue
              fi
            fi
            while IFS= read -r nickname; do
              [ "$nickname" = ${lib.escapeShellArg caNickname} ] && continue
              "$certutil" -D -d "sql:$dir" -n "$nickname" ||
                echo "nssTrust: could not remove the retired CA '$nickname' from $dir" >&2
            done < <(
              "$certutil" -L -d "sql:$dir" |
                sed -n -e 's/^\(srv CA [0-9a-f]*\) .*/\1/p' -e 's/^\(${legacyCaNickname}\) \{2,\}[^ ]* *$/\1/p'
            )
            "$certutil" -A -d "sql:$dir" -i ${rootCA} -n ${lib.escapeShellArg caNickname} -t "C,," ||
              echo "nssTrust: could not add the srv CA to $dir" >&2
          done
        '';
      };

      # `srv daemon install` writes a *real* file at this path, which
      # home-manager would refuse to replace ("Existing file would be
      # clobbered"); force merges onto the unit HM's systemd module generates.
      xdg.configFile."systemd/user/srv-daemon.service".force = true;

      stubbe.setup.srvRoutes = {
        after = [ "sops-nix" ];
        script = ''
          if [ ! -d ${lib.escapeShellArg "${config.xdg.configHome}/srv"} ]; then
            echo "srv-routes: srv not installed (run 'srv install'); skipping."
          elif ! PATH="${config.stubbe.paths.hostPath}:$PATH" ${lib.getExe srvReconcile}; then
            echo "srv-routes: reconciling the declared proxies and redirects failed; will retry next switch." >&2
          fi
        '';
      };
    };
}
