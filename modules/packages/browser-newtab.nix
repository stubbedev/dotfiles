{ self, ... }:
{
  flake.modules.homeManager.browserNewtab =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers {
      # Minimal local new-tab / new-window page.
      #
      # Browsers refuse to inject extension content scripts into the
      # built-in new tab page (about:newtab, chrome://newtab) — that is
      # why Tridactyl and SurfingKeys show their "can't run here" banner
      # there. Pointing the browsers at this plain file:// page instead
      # lets the content script load normally, so the banner never shows
      # and the keybinds work from the moment a tab opens.
      #
      # Wired up by:
      #   Firefox new tab    → `set newtab` in tridactyl.nix
      #   Firefox new window → Homepage policy in firefox/wrappers.nix
      #   Chrome (all)       → enterprise policy in chrome-policy modules
      #
      # The HTML lives as a template under src/ and is read + interpolated
      # by Nix here, the same way the polkit rule files etc. are.
      xdg.dataFile."stubbedev/newtab.html".text = homeLib.substituteFile {
        file = self + "/src/browser/newtab.html";
        # Catppuccin Mocha — base / text / overlay1.
        vars = {
          BG = "#1e1e2e";
          FG = "#cdd6f4";
          MUTED = "#9399b2";
        };
      };
    };
}
