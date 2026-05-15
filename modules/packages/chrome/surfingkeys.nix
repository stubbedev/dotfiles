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
        # Catppuccin Mocha (mauve accent) theme for SurfingKeys, vendored and
        # pinned by content hash so the config is reproducible and offline.
        # To update: bump the commit in the URL and refresh the hash with
        #   nix store prefetch-file --json <url> | jq -r .hash
        catppuccinMocha = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/WalkQuackBack/ctp-surfingkeys/c23fb26f5c33671bf1fbfbe5206ddf7e8b747fc9/themes/mocha/ctp-mocha-mauve.css";
          hash = "sha256-uOXIGDK0EYM9El5mSFPFmcbFYHPL8cKmxNV4hIHsb2M=";
        };
      in
      {
        # SurfingKeys config is a plain JS file. Unlike Tridactyl's rc, it is
        # not auto-discovered — point the extension at this file once:
        #   chrome://extensions → SurfingKeys → enable "Allow access to file
        #     URLs"
        #   SurfingKeys settings → "Load settings from":
        #     file://<homeDir>/.config/surfingkeys/config.js
        # After that the binds + theme below are managed declaratively here.
        #
        # builtins.toJSON turns the CSS into a valid JS string literal, so
        # the theme survives any character without template-literal escaping.
        xdg.configFile."surfingkeys/config.js".text = ''
          // Managed by home-manager — modules/packages/chrome/surfingkeys.nix
          //
          // LazyVim-inspired keymap. Leader = <Space> (LazyVim's <leader>).
          // / n N f gg G are SurfingKeys defaults already and match vim.

          const { api } = window;
          const { map } = api;

          // Tabs == LazyVim buffer navigation (E/R are the SurfingKeys
          // defaults for previous/next tab).
          map('H', 'E');
          map('L', 'R');
          map('[b', 'E');
          map(']b', 'R');

          // Leader groups — LazyVim <leader>b… (buffers) / <leader>f… (find).
          map('<Space>bd', 'x');       // close tab
          map('<Space>bo', 'gxx');     // close other tabs
          map('<Space><Space>', 'T');  // tab picker
          map('<Space>,', 'T');        // tab picker
          map('<Space>ff', 't');       // open URL
          map('<Space>fb', 'b');       // bookmarks
          map('<Space>fr', 'oh');      // history
          map('<Space>fc', 'ox');      // recently closed tab
          map('<Space>e', 'b');        // bookmarks ~ explorer

          // Half-page scroll on <C-d>/<C-u>, like LazyVim (d/u are defaults).
          map('<Ctrl-d>', 'd');
          map('<Ctrl-u>', 'u');

          settings.theme = ${builtins.toJSON (builtins.readFile catppuccinMocha)};
        '';
      }
    );
}
