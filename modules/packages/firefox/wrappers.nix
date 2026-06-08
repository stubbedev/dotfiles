_: {
  linuxOnlyHomeModules.packagesFirefoxWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
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
        #                       point at homeLib.browserNewtabUrl so the new
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
          (homeLib.mkWrappedPackage {
            pkg = pkgs.firefox.override {
              extraPolicies = {
                Homepage = {
                  URL = homeLib.browserNewtabUrl;
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
                // homeLib.browserNewtabUrl) can't pull focus back: content JS
                // cannot steal focus from browser chrome, so the focus() in
                // src/browser/newtab.html loses the race. Do it from chrome
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
}
