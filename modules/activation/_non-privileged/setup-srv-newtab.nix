{ inputs, ... }:
{
  # Register the new-tab static site (~/.local/share/stubbedev/newtab,
  # populated by the browserNewtab activation) with `srv`, so it is served
  # at https://start.local. srv's site state is Docker-backed and lives
  # outside Nix, so this is a best-effort idempotent registration: it skips
  # when the site is already registered or when srv isn't installed yet,
  # and never aborts the activation.
  enableIf = { config, ... }: config.features.browsers && config.features.srv;
  after = [ "browserNewtab" ];
  args =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      srvBin = "${inputs.srv.packages.${pkgs.stdenv.hostPlatform.system}.srv}/bin/srv";
      root = "${config.xdg.dataHome}/stubbedev/newtab";
    in
    {
      actionScript = ''
        # srv shells out to docker (site containers) and sudo (DNS); the
        # home-manager activation runs with a minimal PATH, so make those
        # reachable — covers NixOS (/run/...) and the Ubuntu host (/usr/bin).
        export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

        # `srv install` (Docker, Traefik, mkcert) is a one-time manual step
        # that lives outside Nix. Skip quietly until it has run — the next
        # switch retries — and never abort the activation.
        if [ ! -d "$HOME/.config/srv" ]; then
          echo "srv-newtab: srv not installed (run 'srv install'); skipping."
          exit 0
        fi

        # Register the site once; `srv add` also starts it. Drop its
        # docker-compose progress on stdout (keep stderr for real errors).
        if ! ${srvBin} info start-local >/dev/null 2>&1; then
          ${srvBin} add ${lib.escapeShellArg root} \
            --domain start.local --name start-local --local </dev/null >/dev/null \
            || echo "srv-newtab: 'srv add' failed; will retry next switch." >&2
        fi

        # Ensure it is running — an earlier run may have registered the
        # site while Docker was unreachable, leaving it stopped.
        ${srvBin} start start-local </dev/null >/dev/null 2>&1 || true
      '';
    };
}
