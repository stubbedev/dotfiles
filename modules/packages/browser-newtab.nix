{ self, ... }:
{
  flake.modules.homeManager.browserNewtab =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers (
      let
        # New-tab page rendered from the src/ template (Catppuccin Mocha
        # palette — base / text / overlay1 — substituted at build time).
        newtabHtml = homeLib.substituteFile {
          file = self + "/src/browser/newtab.html";
          vars = {
            BG = "#1e1e2e";
            FG = "#cdd6f4";
            MUTED = "#9399b2";
          };
        };
        # Static-site root that `srv` serves; a stable real directory (not
        # a /nix/store path) so `srv add` registers it once and content
        # updates land without re-running srv.
        newtabRoot = "${config.xdg.dataHome}/stubbedev/newtab";
      in
      {
        # Minimal local new-tab / new-window page.
        #
        # Browsers refuse to inject extension content scripts into the
        # built-in new tab page (about:newtab, chrome://newtab) — that is
        # why Tridactyl and SurfingKeys show their "can't run here" banner
        # there. Pointing the browsers at this page instead avoids it.
        #
        # Served by `srv` as a static site at https://start.local
        # (homeLib.browserNewtabUrl). A file:// page can't be used —
        # Tridactyl's `set newtab` double-opens file:// URLs (tridactyl
        # #530) — and one https URL covers both Firefox and Chrome.
        #
        # This module only installs the static root; registering it is a
        # one-time `srv add` — see the README (BROWSER NEW-TAB PAGE).
        # Anchored after linkGeneration so home-manager's symlink cleanup
        # cannot remove the copied files.
        home.activation.browserNewtab = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          rm -f ${lib.escapeShellArg "${config.xdg.dataHome}/stubbedev/newtab.html"}
          install -Dm644 ${pkgs.writeText "index.html" newtabHtml} \
            ${lib.escapeShellArg "${newtabRoot}/index.html"}
        '';
      }
    );
}
