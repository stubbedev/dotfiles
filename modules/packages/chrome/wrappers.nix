_: {
  linuxOnlyHomeModules.packagesChromeWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # SUID sandbox can't work from /nix/store (read-only, no setuid). Point
      # CHROME_DEVEL_SANDBOX at /dev/null so Chrome rejects it as a SUID
      # candidate and falls back to the userns sandbox; the matching AppArmor
      # profile is installed by setup-chrome-apparmor on Ubuntu 24.04+.
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
        (homeLib.mkWrappedPackage {
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
    };
}
