_: {
  linuxOnlyHomeModules.packagesFirefoxTridactyl =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers (
      let
        # Vendored Tridactyl theme, pinned by content hash so the build is
        # reproducible and works offline (no fetch at browser startup).
        # To update: bump the commit in the URL and refresh the hash with
        #   nix store prefetch-file --json <url> | jq -r .hash
        catppuccinMocha = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/devnullvoid/tridactyl/9de4bee31e4687e90b25e57e927114533863d775/themes/catppuccin-mocha.css";
          hash = "sha256-X6R9FKpOv1W904AvLTdtz3mdqLohcNWjXNNufIs5HNU=";
        };

        # Explicit CSS selector for `hint -c`. Replacing Tridactyl's default
        # element detection (which also hints anything with cursor:pointer,
        # a bare [tabindex], etc. — far too much on modern SPAs) with this
        # list keeps hints to genuinely interactive elements.
        hintSelector = builtins.concatStringsSep ", " [
          "a"
          "area"
          "button"
          "input:not([disabled]):not([type=hidden])"
          "select"
          "textarea"
          "summary"
          "details"
          "iframe"
          "[role=link]"
          "[role=button]"
          "[role=tab]"
          "[role=checkbox]"
          "[role=menuitem]"
          "[onclick]"
          "[contenteditable=true]"
        ];
      in
      {
        # Native messenger. Tridactyl can only read its rc file, discover
        # local themes, and run `:source` when this host program is both
        # installed and registered with Firefox.
        home.packages = [ pkgs.tridactyl-native ];

        home.file =
          let
            # The manifest carries an absolute /nix/store path to the
            # native_main binary, so symlinking it verbatim is enough.
            manifest = "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";
          in
          {
            # Firefox's pre-XDG per-user native-messaging-host directory.
            ".mozilla/native-messaging-hosts/tridactyl.json".source = manifest;
            # Firefox 147+ XDG layout (this host strips MOZ_LEGACY_PROFILES
            # in modules/packages/firefox/wrappers.nix, so the profile and
            # this lookup move under ~/.config/mozilla). Both are listed so
            # registration works regardless of which path Firefox uses.
            ".config/mozilla/native-messaging-hosts/tridactyl.json".source = manifest;
          };

        xdg.configFile = {
          # Auto-sourced by Tridactyl on every browser startup.
          #
          # Keymap is LazyVim-inspired: leader = <Space> (LazyVim's
          # <leader>), <S-h>/<S-l> + [b/]b cycle tabs (LazyVim buffer
          # nav), and / n N gg G stay as the shared vim defaults.
          "tridactyl/tridactylrc".text = ''
            " --- Search (vim / LazyVim) ---
            bind / fillcmdline find
            bind ? fillcmdline find -?
            bind n findnext 1
            bind N findnext -1
            " <Esc> clears the search highlight, like LazyVim, while still
            " doing Tridactyl's default normal-mode reset.
            bind <Escape> composite nohlsearch ; mode normal ; hidecmdline

            " --- Hints ---
            " -c restricts hints to an explicit CSS selector, dropping the
            " default cursor:pointer / bare-tabindex heuristics that hint
            " far too many nodes on modern sites. `;f` keeps the unfiltered
            " hint mode for the occasional JS-only clickable <div>.
            bind f hint -c ${hintSelector}
            bind F hint -bc ${hintSelector}
            bind ;f hint

            " --- Tabs == LazyVim buffers ---
            " Overrides Tridactyl's default H/L (history back/forward);
            " history stays on Alt+Left / Alt+Right.
            bind H tabprev
            bind L tabnext
            bind [b tabprev
            bind ]b tabnext

            " --- Leader = <Space> (LazyVim) ---
            " <leader>b… buffers (tabs)
            bind <Space>bd tabclose
            bind <Space>bo tabonly
            bind <Space>bp pin
            bind <Space>bh tabclosealltoleft
            bind <Space>bl tabclosealltoright
            " <leader><leader> / <leader>, pickers
            bind <Space><Space> fillcmdline tab
            bind <Space>, fillcmdline taball
            " <leader>f… find / open
            bind <Space>ff fillcmdline open
            bind <Space>ft fillcmdline tabopen
            bind <Space>fw fillcmdline winopen
            " <leader>q… quit
            bind <Space>qt tabclose
            bind <Space>qq qall

            " --- Minimal new-tab page (skips Tridactyl's notice page) ---
            " Served by srv at https://start.local. `set newtab` double-opens
            " file:// URLs (tridactyl#530), so an https URL is used instead.
            set newtab ${homeLib.browserNewtabUrl}

            colourscheme catppuccin-mocha
          '';

          # The native messenger scans this directory; any .css here becomes
          # selectable via `:colourscheme` by its file name (no --url fetch).
          "tridactyl/themes/catppuccin-mocha.css".source = catppuccinMocha;
        };
      }
    );
}
