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
            (homeLib.gfx pkgs.google-chrome)
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
