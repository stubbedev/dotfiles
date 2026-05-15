_: {
  linuxOnlyHomeModules.packagesChromeSurfingkeys =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers (
      let
        # Catppuccin Mocha theme for SurfingKeys (mauve accent), from
        # github.com/WalkQuackBack/ctp-surfingkeys — vendored and pinned by
        # content hash so the config is reproducible and offline. To update:
        # bump the commit and refresh the hash with
        #   nix store prefetch-file --json <url> | jq -r .hash
        catppuccinMocha = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/WalkQuackBack/ctp-surfingkeys/c23fb26f5c33671bf1fbfbe5206ddf7e8b747fc9/themes/mocha/ctp-mocha-mauve.css";
          hash = "sha256-uOXIGDK0EYM9El5mSFPFmcbFYHPL8cKmxNV4hIHsb2M=";
        };
      in
      {
        # SurfingKeys can't be configured by policy — its config lives in
        # extension storage, which Chrome walls off. Point the extension at
        # this file once, in Chrome + SurfingKeys' own settings UI. ALL of
        # these are required; SurfingKeys is Manifest V3, so without "Allow
        # User Scripts" (or Advanced mode) it cannot execute the JS config
        # and stays on its default, unstyled UI:
        #   1. chrome://extensions → enable Developer mode
        #   2. chrome://extensions → SurfingKeys → Details → enable both
        #      "Allow User Scripts" and "Allow access to file URLs"
        #   3. SurfingKeys settings → turn on Advanced mode
        #   4. SurfingKeys settings → "Load settings from":
        #      file://<homeDir>/.config/surfingkeys/config.js
        # See the README (SURFINGKEYS (CHROME) SETUP).
        #
        # builtins.toJSON turns the CSS into a valid JS string literal, so
        # the theme survives any character without template-literal escaping.
        xdg.configFile."surfingkeys/config.js".text = ''
          // Managed by home-manager — modules/packages/chrome/surfingkeys.nix
          //
          // LazyVim-inspired keymap. Leader = <Space> (LazyVim's <leader>).
          // / n N f gg G are SurfingKeys defaults already and match vim.
          //
          // `api` and `settings` are globals in the SurfingKeys config
          // context — use them directly, exactly as SurfingKeys' own
          // shipped example does. (`const { api } = window` is wrong: api
          // is not a window property, so it would throw and abort the
          // whole config — no theme, no binds.)

          // Tabs == LazyVim buffer navigation (E/R are the SurfingKeys
          // defaults for previous/next tab).
          api.map('H', 'E');
          api.map('L', 'R');
          api.map('[b', 'E');
          api.map(']b', 'R');

          // Leader groups — LazyVim <leader>b… (buffers) / <leader>f… (find).
          api.map('<Space>bd', 'x');       // close tab
          api.map('<Space>bo', 'gxx');     // close other tabs
          api.map('<Space><Space>', 'T');  // tab picker
          api.map('<Space>,', 'T');        // tab picker
          api.map('<Space>ff', 't');       // open URL
          api.map('<Space>fb', 'b');       // bookmarks
          api.map('<Space>fr', 'oh');      // history
          api.map('<Space>fc', 'ox');      // recently closed tab
          api.map('<Space>e', 'b');        // bookmarks ~ explorer

          // Half-page scroll on <C-d>/<C-u>, like LazyVim (d/u are defaults).
          api.map('<Ctrl-d>', 'd');
          api.map('<Ctrl-u>', 'u');

          // --- Appearance ---
          // Omnibar at the bottom of the window, like Tridactyl's command
          // line; Catppuccin Mocha theme for the omnibar, hints and status.
          settings.omnibarPosition = "bottom";
          settings.theme = ${builtins.toJSON (builtins.readFile catppuccinMocha)};
        '';
      }
    );
}
