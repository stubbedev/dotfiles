_: {
  linuxOnlyHomeModules.packagesChromeSurfingkeys =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers {
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
      # The theme (src/browser/surfingkeys-theme.css) re-expresses the
      # Tridactyl Catppuccin Mocha command-line styling against SurfingKeys'
      # omnibar DOM. builtins.toJSON makes it a safe JS string literal.
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

        // Keymap mirrors the Tridactyl tridactylrc binds (see
        // modules/packages/firefox/tridactyl.nix). / ? n N f gg G already
        // match — they are SurfingKeys defaults and vim-standard.

        // Tabs — Tridactyl H/L + [b/]b (E/R = SurfingKeys prev/next tab).
        api.map('H', 'E');
        api.map('L', 'R');
        api.map('[b', 'E');
        api.map(']b', 'R');

        // <Space> leader — mirrors the tridactylrc <Space> binds.
        api.map('<Space>bd', 'x');       // tabclose
        api.map('<Space>bo', 'gxx');     // tabonly (close other tabs)
        api.map('<Space>bh', 'gx0');     // tabclosealltoleft
        api.map('<Space>bl', 'gx$');     // tabclosealltoright
        api.map('<Space><Space>', 'T');  // fillcmdline tab
        api.map('<Space>,', 'T');        // fillcmdline taball
        api.map('<Space>ff', 't');       // fillcmdline open
        api.map('<Space>ft', 't');       // fillcmdline tabopen
        api.map('<Space>qt', 'x');       // tabclose
        // Tridactyl <Space>bp (pin), <Space>fw (winopen) and <Space>qq
        // (qall) have no SurfingKeys equivalent — pinning is handled by
        // the Tab Pinner extension instead.

        // Hints — Tridactyl f (kept, SurfingKeys default) and F.
        api.map('F', 'gf');              // hint into a background tab

        // Half-page scroll on <C-d>/<C-u> (d/u are SurfingKeys defaults).
        api.map('<Ctrl-d>', 'd');
        api.map('<Ctrl-u>', 'u');

        // --- Appearance: mirror the Tridactyl Catppuccin command line ---
        // "middle" = centred box, input on top, results below — like
        // Tridactyl. ("bottom" flips it: input at the bottom, results above.)
        settings.omnibarPosition = "middle";
        settings.showModeStatus = true;      // always-on mode indicator
        settings.theme = ${builtins.toJSON (homeLib.xdgContent "browser/surfingkeys-theme.css")};
      '';
    };
}
