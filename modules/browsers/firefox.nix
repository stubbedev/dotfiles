# Firefox: the nixGL wrapper, the policies that force-install the managed
# add-ons, and Tridactyl (the native messenger, its rc file and its theme).
_: {
  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.browsers (

      let
        # Firefox add-ons force-installed via the Extensions policy, keyed
        # by AMO id -> AMO slug. install_url uses AMO's `latest` redirect so
        # each tracks new releases automatically. Force-installed add-ons
        # cannot be removed or disabled from within Firefox — drop an entry
        # here to un-manage it.
        firefoxAddons = {
          "tridactyl.vim@cmcaine.co.uk" = "tridactyl-vim";
          "jid1-xUfzOsOFlzSOXg@jetpack" = "reddit-enhancement-suite";
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
          "uBlock0@raymondhill.net" = "ublock-origin";
          "{7719f622-a980-4a30-ba6a-1a5ad11b677c}" = "pin-unpin-tab";
        };
      in
      {
        # Wrap firefox in nixGL, then strip MOZ_LEGACY_PROFILES so the binary
        # falls back to its built-in XDG-compliant default (Firefox 147+).
        # nixpkgs hardcodes MOZ_LEGACY_PROFILES=1 in its wrapper to keep the
        # historical ~/.mozilla/firefox path; we want ~/.config/mozilla/firefox
        # to match the previous programs.firefox setup.
        #
        # libxul.so links against libpng-apng (animated PNG fork) which has
        # png_get_next_frame_delay_num. nixpkgs' firefox wrapper doesn't put
        # libpng-apng on LD_LIBRARY_PATH, and ld.so.cache happens to find
        # /usr/lib/libpng16.so.16 (stock libpng, no APNG symbols) before
        # libxul.so's RUNPATH is consulted. --prefix forces the right one.
        #
        # Upstream's firefox.desktop uses Exec=firefox (PATH-resolved), so
        # bundling upstream alongside the wrapper picks up icons and the
        # desktop entry while still routing the binary through our wrapper.
        #
        # extraPolicies bakes a distribution/policies.json into the Firefox
        # package:
        #   Homepage          — Firefox always opens the home page for a new
        #                       window, so this covers new windows. The new
        #                       *tab* page has no Firefox policy and is
        #                       handled by Tridactyl's `set newtab`; both
        #                       point at pkgs.stubbe.newtabUrl so the new
        #                       tab and new window load the same page.
        #   ExtensionSettings — force-installs the managed add-ons from AMO.
        #
        # extraPrefs is an autoconfig (.cfg) snippet — unlike the Preferences
        # policy it can set any pref. browser.tabs.inTitlebar = 0 forces the
        # system title bar (what Customize > Title Bar toggles); lockPref so
        # it can't be switched off.
        #
        # Touchpad: MOZ_ENABLE_WAYLAND routes Firefox through GTK's Wayland
        # backend so libinput gesture events (two-finger scroll, pinch,
        # horizontal swipe) reach the browser. Under XWayland those events
        # are swallowed unless MOZ_USE_XINPUT2 is set, so set both for the
        # X11-fallback path. apz.gtk.touchpad_pinch.enabled enables
        # pinch-to-zoom on the GTK/Wayland path; browser.gesture.swipe.*
        # binds horizontal swipes to history navigation (default values,
        # re-asserted in case a profile overrode them).
        home.packages = [
          (config.stubbe.gfx.bundle {
            pkg = pkgs.firefox.override {
              extraPolicies = {
                Homepage = {
                  URL = pkgs.stubbe.newtabUrl;
                  StartPage = "homepage";
                };
                ExtensionSettings = builtins.mapAttrs (_id: slug: {
                  installation_mode = "force_installed";
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
                }) firefoxAddons;
              };
              extraPrefs = ''
                lockPref("browser.tabs.inTitlebar", 0);
                lockPref("apz.allow_zooming", true);
                lockPref("apz.gtk.touchpad_pinch.enabled", true);
                lockPref("apz.gtk.kinetic_scroll.enabled", true);
                lockPref("widget.disable-swipe-tracker", false);
                lockPref("browser.gesture.swipe.left", "Browser:BackOrBackDuplicate");
                lockPref("browser.gesture.swipe.right", "Browser:ForwardOrForwardDuplicate");

                // --- Focus page content on new tab / new window ---
                // Firefox parks the cursor in the urlbar for about:newtab,
                // and Tridactyl's `set newtab` redirect (-> https://start.local,
                // pkgs.stubbe.newtabUrl) can't pull focus back: content JS
                // cannot steal focus from browser chrome, so the focus() in
                // src/browsers/newtab.html loses the race. Do it from chrome
                // instead — this autoconfig snippet runs privileged. Hook each
                // browser window and refocus the selected <browser> shortly
                // after the window loads or a tab opens. See tridactyl#4967.
                try {
                  Services.obs.addObserver({
                    observe(subject) {
                      const win = subject;
                      win.addEventListener("load", () => {
                        const gBrowser = win.gBrowser;
                        if (!gBrowser) return;
                        // Delay past Firefox's own urlbar focus, then take it
                        // back — but only if the tab is still the active one
                        // (skips background/middle-click tabs).
                        const focusContent = (tab) => win.setTimeout(() => {
                          if (gBrowser.selectedTab === tab) {
                            gBrowser.selectedBrowser.focus();
                          }
                        }, 120);
                        focusContent(gBrowser.selectedTab);
                        gBrowser.tabContainer.addEventListener("TabOpen", (e) => {
                          focusContent(e.target);
                        });
                      }, { once: true });
                    },
                  }, "domwindowopened");
                } catch (e) {
                  Components.utils.reportError(e);
                }
              '';
            };
            env = {
              MOZ_ENABLE_WAYLAND = "1";
              MOZ_USE_XINPUT2 = "1";
            };
            unset = [ "MOZ_LEGACY_PROFILES" ];
            prefix.LD_LIBRARY_PATH = "${pkgs.libpng.out}/lib";
          })
        ];
      }
    );

  flake.modules.homeManager.tridactyl =
    {
      config,
      lib,
      pkgs,
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
            # in modules/browsers/firefox.nix, so the profile and
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
            set newtab ${pkgs.stubbe.newtabUrl}

            colourscheme catppuccin-mocha
          '';

          # The native messenger scans this directory; any .css here becomes
          # selectable via `:colourscheme` by its file name (no --url fetch).
          "tridactyl/themes/catppuccin-mocha.css".source = catppuccinMocha;
        };
      }
    );
}
