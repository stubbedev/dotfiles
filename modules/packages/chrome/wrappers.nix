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
          pkg = pkgs.google-chrome.override {
            commandLineArgs = builtins.concatStringsSep " " [
              "--enable-features=WaylandWindowDecorations,WaylandSessionManagement,AcceleratedVideoEncoder"
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
