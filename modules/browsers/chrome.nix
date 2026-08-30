_: {
  flake.modules.homeManager.chrome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      c = pkgs.stubbe.withHash;

      surfingkeysTheme = ''
        .sk_theme {
          /* Tridactyl --font (themes/catppuccin-mocha.css). */
          font-family: "Monaspace Krypton", "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
          background: ${c.base};
          color: ${c.text};
        }

        .sk_theme input { color: ${c.text}; }
        .sk_theme .url { color: ${c.green}; }              /* Tridactyl --completions-url (green) */
        .sk_theme .annotation { color: ${c.subtext0}; }
        .sk_theme .omnibar_highlight { color: ${c.mauve}; } /* search match (mauve) */
        .sk_theme .omnibar_folder,
        .sk_theme .omnibar_timestamp,
        .sk_theme .omnibar_visitcount { color: ${c.overlay0}; }
        .sk_theme .feature_name,
        .sk_theme .feature_name span { color: ${c.peach}; } /* Tridactyl section header (peach) */
        .sk_theme .separator { display: none; } /* hide the ➤ prompt arrow */
        .sk_theme .prompt,
        .sk_theme .resultPage { color: ${c.lavender}; }

        /* Omnibar — Tridactyl's command line: flat dark, 2px lavender border. */
        #sk_omnibar {
          background: ${c.base};
          border: 2px solid ${c.lavender};
          box-shadow: 0 0 20px ${c.crust};
        }
        /* Exact Tridactyl placement: its #cmdline_iframe is top:25% left:10%
           width:80%. SurfingKeys' #sk_omnibar is already left:10% width:80%;
           only the vertical offset differs (.sk_omnibar_middle defaults to
           top:10%), so pin it to 25%. ID+class outranks the stock class. */
        #sk_omnibar.sk_omnibar_middle {
          top: 25%;
        }
        #sk_omnibarSearchArea {
          border-bottom: 1px solid ${c.surface0};
        }
        #sk_omnibarSearchArea input,
        #sk_omnibarSearchArea > input {
          background: transparent;
          color: ${c.text};
          font-size: 1.5rem;          /* Tridactyl #tridactyl-input */
        }

        /* Result rows — flat list, no favicon icons (Tridactyl hides td.icon).
           0.8rem matches Tridactyl's #completions table (smaller than the input). */
        #sk_omnibarSearchResult .icon { display: none !important; }
        #sk_omnibarSearchResult > ul > li,
        .sk_theme #sk_omnibarSearchResult > ul > li:nth-child(odd) {
          background: ${c.base};
          color: ${c.text};
          font-size: 0.8rem;
        }
        #sk_omnibarSearchResult .title { color: ${c.blue}; }   /* Tridactyl --completions-title (blue) */
        #sk_omnibarSearchResult .url { color: ${c.green}; }
        .sk_theme #sk_omnibarSearchResult > ul > li.focused {
          background: ${c.mantle};                                /* Tridactyl --currentline (mantle) */
          font-weight: bold;
        }
        #sk_omnibarSearchResult > ul > li.focused .title { color: ${c.pink}; } /* focused title (pink) */
        #sk_omnibarSearchResult > ul > li.focused .url { color: ${c.green}; }

        /* Mode indicator — bottom-right box, mirroring Tridactyl's status
           indicator. settings.showModeStatus keeps it always visible. */
        #sk_status {
          position: fixed !important;
          bottom: 0 !important;
          right: 0 !important;
          left: auto !important;
          background: ${c.base};
          color: ${c.text};
          border: 1px solid ${c.lavender};
          font-size: 12pt;
          padding: 0.3em 0.8em;
        }

        /* which-key (pending-key candidates) — full-width bar across the bottom
           with larger text, instead of the stock small bottom-right box. */
        #sk_keystroke {
          background: ${c.base};
          color: ${c.text};
          left: 0;
          right: 0;
          width: 100%;
          float: none;
          border-top: 2px solid ${c.lavender};
          font-size: 14pt;
          padding: 0.6em 1em;
        }
        #sk_keystroke kbd { font-size: 1em; }

        /* usage / help / editor popups */
        #sk_usage,
        #sk_popup,
        #sk_editor {
          background: ${c.base};
          color: ${c.text};
        }
        .sk_theme kbd {
          background: ${c.surface0};
          color: ${c.text};
          border-color: ${c.surface1};
        }
      '';

      # The SUID sandbox cannot work from the read-only store, so pointing
      # CHROME_DEVEL_SANDBOX at /dev/null forces the userns sandbox instead.
      # The join excludes upstream because its .desktop entry is replaced below.
      chromeDesktop = pkgs.makeDesktopItem {
        name = "com.google.Chrome";
        desktopName = "Google Chrome";
        genericName = "Web Browser";
        comment = "Access the Internet";
        exec = "google-chrome-stable %U";
        icon = "google-chrome";
        type = "Application";
        categories = [
          "Network"
          "WebBrowser"
        ];
        mimeTypes = [
          "application/pdf"
          "application/rdf+xml"
          "application/rss+xml"
          "application/xhtml+xml"
          "application/xhtml_xml"
          "application/xml"
          "image/gif"
          "image/jpeg"
          "image/png"
          "image/webp"
          "text/html"
          "text/xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/google-chrome"
        ];
        startupNotify = true;
        terminal = false;
        actions = {
          new-window = {
            name = "New Window";
            exec = "google-chrome-stable";
          };
          new-private-window = {
            name = "New Incognito Window";
            exec = "google-chrome-stable --incognito";
          };
        };
      };
    in
    lib.mkIf config.features.browsers {
      home.packages = [
        (config.stubbe.gfx.bundle {
          # Chrome keeps only the LAST --enable-features, and chrome://flags is
          # appended after the command line, so this list is authoritative only
          # while that page stays at defaults.
          # WaylandWindowDecorations is restated because this flag overrides the
          # one the nixpkgs wrapper passes earlier. AcceleratedVideoEncoder is
          # VA-API encode; without it camera calls encode on CPU.
          # Revert --enable-zero-copy first if tab contents ever render corrupted.
          # Tried and reverted: SkiaGraphite is refused by a platform safety
          # guard the flag cannot override; RawDraw, EnableDrDc and TreesInViz
          # each rendered the viewport blank white.
          # Vulkan stays CPU-fallback because Chrome will not composite via
          # Vulkan on Wayland. GL is hardware-accelerated, so do not add
          # --ozone-platform=x11 to "fix" it.
          pkg = pkgs.google-chrome.override {
            commandLineArgs = lib.concatStringsSep " " [
              "--enable-features=WaylandWindowDecorations,WaylandSessionManagement,AcceleratedVideoEncoder"
              "--enable-zero-copy"
              "--ignore-gpu-blocklist"
            ];
          };
          env.CHROME_DEVEL_SANDBOX = "/dev/null";
          includeUpstream = false;
          extraPaths = [ chromeDesktop ];
        })
      ];

      # SurfingKeys cannot be configured by policy: its config lives in
      # extension storage. Pointing the extension at this file is a one-time
      # manual step -- see the README (SURFINGKEYS (CHROME) SETUP).
      xdg.configFile."surfingkeys/config.js".text = ''
        // Managed by home-manager — modules/browsers/chrome.nix
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
        // modules/browsers/firefox.nix). / ? n N f gg G already
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
        settings.theme = ${builtins.toJSON surfingkeysTheme};
      '';

      # Ubuntu 24.04+ gates the userns sandbox on a matching AppArmor profile.
      stubbe.setup.chromeApparmor = pkgs.stubbe.apparmorSetup {
        appName = "Chrome";
        profileName = "nix-google-chrome-stable";
        programGlob = "/nix/store/*/share/google/chrome/{chrome,chrome-sandbox}";
      };

      stubbe.setup.chromePolicy = {
        privileged = true;
        title = "Installing Chrome new-tab policy";
        body = ''
          Drop a Chrome enterprise policy at
          /etc/opt/chrome/policies/managed/stubbedev-newtab.json. It points the
          new tab page, new windows and the homepage at the local new-tab page
          (https://start.local, served by srv), and force-installs the managed
          extensions (SurfingKeys, Bitwarden, React DevTools, …).
        '';
        script = pkgs.stubbe.installFile {
          source = (pkgs.formats.json { }).generate "stubbedev-newtab.json" (
            pkgs.stubbe.chromePolicy pkgs.stubbe.newtabUrl
          );
          target = "/etc/opt/chrome/policies/managed/stubbedev-newtab.json";
        };
      };
    };
}
