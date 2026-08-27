# The local new-tab / new-window page, and its registration with srv.
#
# Browsers refuse to inject extension content scripts into the built-in new tab
# page (about:newtab, chrome://newtab) — that is why Tridactyl and SurfingKeys
# show a "can't run here" banner there. Pointing both browsers at this page
# instead avoids it. It is served over https by srv rather than file://, because
# Tridactyl's `set newtab` double-opens file:// URLs (tridactyl#530) and one
# https URL works for both browsers.
{ inputs, ... }:
{
  flake.modules.homeManager.newtab =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      c = pkgs.stubbe.withHash;
      # A stable real directory, not a store path, so `srv add` registers it
      # once and content updates land without re-running srv.
      root = "${config.xdg.dataHome}/stubbedev/newtab";
      page = pkgs.stubbe.render "src/browsers/newtab.html" {
        BG = c.base;
        FG = c.text;
        MUTED = c.overlay2;
      };
      srvBin = lib.getExe' inputs.srv.packages.${pkgs.stdenv.hostPlatform.system}.srv "srv";
    in
    lib.mkIf config.features.browsers {
      # Only the static root is installed here; registering it is the setup
      # below. Ordered after linkGeneration so home-manager's symlink cleanup
      # cannot remove the copied file.
      stubbe.mutable."${lib.removePrefix "${config.home.homeDirectory}/" root}/index.html" = {
        method = "copy";
        source = page;
      };

      # Register the site with srv so it is served at https://start.local. srv's
      # site state is Docker-backed and lives outside Nix, so this is a
      # best-effort idempotent registration: it skips when the site is already
      # registered or srv is not installed yet, and never aborts activation.
      stubbe.setup.srvNewtab = lib.mkIf config.features.srv {
        after = [ "mutableFiles" ];
        script = ''
          # srv shells out to docker (site containers) and sudo (DNS); the
          # activation runs with a minimal PATH, so make those reachable —
          # covering NixOS (/run/…) and a standalone-HM distro (/usr/bin).
          export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

          # `srv install` (Docker, Traefik, mkcert) is a one-time manual step
          # that lives outside Nix. Skip quietly until it has run — the next
          # switch retries — and never abort the activation.
          if [ ! -d "$HOME/.config/srv" ]; then
            echo "srv-newtab: srv not installed (run 'srv install'); skipping."
            exit 0
          fi

          # Register once; `srv add` also starts it. Its docker-compose progress
          # goes to /dev/null, stderr keeps real errors.
          if ! ${srvBin} info start-local >/dev/null 2>&1; then
            ${srvBin} add ${lib.escapeShellArg root} \
              --domain start.local --name start-local --local </dev/null >/dev/null \
              || echo "srv-newtab: 'srv add' failed; will retry next switch." >&2
          fi

          # Ensure it is running — an earlier run may have registered the site
          # while Docker was unreachable, leaving it stopped.
          ${srvBin} start start-local </dev/null >/dev/null 2>&1 || true
        '';
      };
    };
}
