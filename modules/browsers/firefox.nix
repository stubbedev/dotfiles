{ inputs, ... }:
{
  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.browsers (
      let
        # Force-installed add-ons cannot be removed or disabled from within
        # Firefox; drop an entry here to un-manage it.
        firefoxAddons = {
          "tridactyl.vim@cmcaine.co.uk" = "tridactyl-vim";
          "jid1-xUfzOsOFlzSOXg@jetpack" = "reddit-enhancement-suite";
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
          "uBlock0@raymondhill.net" = "ublock-origin";
          "{7719f622-a980-4a30-ba6a-1a5ad11b677c}" = "pin-unpin-tab";
        };

        # toJSON renders each value in its own JS literal form, so the
        # int/bool/string distinction is the Nix value's rather than a quoting
        # detail to get right by hand. Locked means unchangeable in about:config.
        lockedPrefs = {
          "browser.tabs.inTitlebar" = 0;
          "apz.allow_zooming" = true;
          "apz.gtk.touchpad_pinch.enabled" = true;
          "apz.gtk.kinetic_scroll.enabled" = true;
          "widget.disable-swipe-tracker" = false;
          "browser.gesture.swipe.left" = "Browser:BackOrBackDuplicate";
          "browser.gesture.swipe.right" = "Browser:ForwardOrForwardDuplicate";
        };

        # Vendored so nothing is fetched at browser startup.
        catppuccinMocha = "${inputs.tridactyl-theme-src}/themes/catppuccin-mocha.css";

        # Tridactyl's default detection also hints anything with cursor:pointer
        # or a bare [tabindex], which is far too much on a modern SPA.
        hintSelector = lib.concatStringsSep ", " [
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
        # nixpkgs hardcodes MOZ_LEGACY_PROFILES=1 to keep the historical
        # ~/.mozilla/firefox path; stripping it gets the XDG default instead.
        # libxul.so needs libpng-apng, which the nixpkgs wrapper leaves off
        # LD_LIBRARY_PATH, so ld.so.cache finds the host's stock libpng first.
        # firefox.desktop uses a PATH-resolved Exec, so bundling upstream gets
        # its icons and desktop entry while the wrapper still wins.
        # The new *tab* page has no Firefox policy and is handled by Tridactyl's
        # `set newtab`; both point at pkgs.stubbe.newtabUrl so new tab and new
        #                       tab and new window load the same page.
        # Under XWayland libinput gesture events are swallowed unless
        # MOZ_USE_XINPUT2 is set, so both are set for the X11-fallback path. apz.gtk.touchpad_pinch.enabled enables
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
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (
                    key: value: "lockPref(${builtins.toJSON key}, ${builtins.toJSON value});"
                  ) lockedPrefs
                )}

                // --- Focus page content on new tab / new window ---
                // Firefox parks the cursor in the urlbar for about:newtab,
                // and Tridactyl's `set newtab` redirect (-> https://start.local,
                // pkgs.stubbe.newtabUrl) can't pull focus back: content JS
                // cannot steal focus from browser chrome, so the focus() in
                // the newtab page (modules/browsers/newtab.nix) loses the race. Do it from chrome
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
          # Without the registered native messenger Tridactyl cannot read its rc
          # file, discover local themes or run `:source`.
          pkgs.tridactyl-native
        ];

        home.file =
          let
            # The manifest carries an absolute store path, so a symlink suffices.
            manifest = "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";
          in
          {
            ".mozilla/native-messaging-hosts/tridactyl.json".source = manifest;
            # Both layouts are listed so registration works whichever path
            # Firefox ends up using.
            ".config/mozilla/native-messaging-hosts/tridactyl.json".source = manifest;
          };

        xdg.configFile = {
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

          "tridactyl/themes/catppuccin-mocha.css".source = catppuccinMocha;
        };
      }
    );
}
