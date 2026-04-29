_: {
  flake.modules.homeManager.programsChrome =
    {
      lib,
      config,
      pkgs,
      homeLib,
      ...
    }:
    lib.mkIf config.features.browsers {
      home.packages = [
        (pkgs.symlinkJoin {
          name = "google-chrome-stable";
          paths = [
            (
              # SUID sandbox can't work from /nix/store (read-only, no
              # setuid). Point CHROME_DEVEL_SANDBOX at /dev/null so
              # Chrome rejects it as a SUID candidate and falls back to
              # the userns sandbox; the matching AppArmor profile is
              # installed by the setup-chrome-apparmor activation on
              # Ubuntu 24.04+.
              let
                gfxChrome = homeLib.gfx pkgs.google-chrome;
              in
              pkgs.runCommand "google-chrome-stable-no-suid"
                { nativeBuildInputs = [ pkgs.makeWrapper ]; }
                ''
                  makeWrapper ${gfxChrome}/bin/google-chrome-stable \
                    $out/bin/google-chrome-stable \
                    --set CHROME_DEVEL_SANDBOX /dev/null
                ''
            )
            (pkgs.makeDesktopItem {
              name = "com.google.Chrome";
              desktopName = "Google Chrome";
              genericName = "Web Browser";
              comment = "Access the Internet";
              exec = "google-chrome-stable %U";
              icon = "google-chrome";
              type = "Application";
              categories = [ "Network" "WebBrowser" ];
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
            })
          ];
        })
      ];
    };
}
