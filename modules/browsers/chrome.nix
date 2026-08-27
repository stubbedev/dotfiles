# Google Chrome: the nixGL wrapper, the enterprise policy that force-installs
# the managed extensions, and the SurfingKeys config the policy cannot reach.
_: {
  flake.modules.homeManager.chrome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # SUID sandbox can't work from /nix/store (read-only, no setuid). Point
      # CHROME_DEVEL_SANDBOX at /dev/null so Chrome rejects it as a SUID
      # candidate and falls back to the userns sandbox; the matching AppArmor
      # profile is installed by the chromeApparmor setup below on Ubuntu 24.04+.
      #
      # We replace upstream's google-chrome.desktop with our own (so we
      # control the actions and MIME list), so the join excludes upstream.
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
          # Chrome keeps only the LAST --enable-features occurrence, and
          # chrome://flags experiments are appended after the command line —
          # so this list is only authoritative while the flags page stays at
          # defaults. Keep feature flags here, not in chrome://flags.
          #
          # WaylandWindowDecorations: re-stated because this --enable-features
          #   overrides the one nixpkgs' wrapper passes earlier on the line.
          # WaylandSessionManagement: window-position session restore
          #   (was previously set via chrome://flags).
          # AcceleratedVideoEncoder: VA-API video encode — without it camera
          #   calls (Meet/Zoom) encode on CPU; decode is already hardware.
          #
          # --enable-zero-copy: raster tiles written straight into GPU
          #   memory instead of upload copies — iGPU with unified memory is
          #   exactly the case it's for. Falls back per-buffer if the
          #   format can't map. Revert first if tab contents ever render
          #   corrupted.
          #
          # Tried for max perf/mem, all reverted — none took on this
          # Chrome/Wayland/LNL combo:
          #   SkiaGraphite: refused by the platform safety guard
          #     ("Enabling Graphite on a not-yet-supported platform is
          #     disallowed for safety", gpu_finch_features.cc) — the
          #     --enable-features flag can't override it. Dead + log spam.
          #   RawDraw / EnableDrDc / TreesInViz: caused blank-white render
          #     (whole viewport unpainted).
          #   Re-try individually when defaults flip.
          #
          # Vulkan stays CPU-fallback under Wayland (Chrome won't composite
          # via Vulkan on Wayland). Not a regression: GL is the active path
          # and IS hardware-accelerated on the iGPU. Leave it — do not add
          # --ozone-platform=x11 to "fix" Vulkan; Wayland is intentional.
          pkg = pkgs.google-chrome.override {
            commandLineArgs = builtins.concatStringsSep " " [
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
      # The theme (src/browsers/surfingkeys-theme.css) re-expresses the
      # Tridactyl Catppuccin Mocha command-line styling against SurfingKeys'
      # omnibar DOM. builtins.toJSON makes it a safe JS string literal.
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
        settings.theme = ${
          builtins.toJSON (
            builtins.readFile (pkgs.stubbe.renderPalette "src/browsers/surfingkeys-theme.css" { })
          )
        };
      '';

      # Ubuntu 24.04+ restricts unprivileged user namespaces — which the
      # userns sandbox the wrapper above falls back to needs — to binaries with
      # a matching AppArmor profile.
      stubbe.setup.chromeApparmor = pkgs.stubbe.apparmorSetup {
        appName = "Chrome";
        profileName = "nix-google-chrome-stable";
        programGlob = "/nix/store/*/share/google/chrome/{chrome,chrome-sandbox}";
      };

      # The enterprise policy, on the non-NixOS side. Chrome reads policies
      # from /etc/opt/chrome/policies/managed/; the body is shared with the
      # NixOS half in modules/browsers/policy.nix.
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
        script = pkgs.stubbe.installText {
          name = "stubbedev-newtab.json";
          target = "/etc/opt/chrome/policies/managed/stubbedev-newtab.json";
          text = builtins.toJSON (pkgs.stubbe.chromePolicy pkgs.stubbe.newtabUrl) + "\n";
        };
      };
    };
}
