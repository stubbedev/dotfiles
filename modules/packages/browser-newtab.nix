_: {
  flake.modules.homeManager.browserNewtab =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers {
      # Minimal local new-tab / new-window page.
      #
      # Browsers refuse to inject extension content scripts into the
      # built-in new tab page (about:newtab, chrome://newtab) — that is
      # why Tridactyl and SurfingKeys show their "can't run here" banner
      # there. Pointing the browsers at this plain file:// page instead
      # lets the content script load normally, so the banner never shows
      # and the keybinds work from the moment a tab opens.
      #
      # Wired up by:
      #   Firefox new tab    → `set newtab` in tridactyl.nix
      #   Firefox new window → Homepage policy in firefox/wrappers.nix
      #   Chrome (all)       → enterprise policy in chrome-policy modules
      xdg.dataFile."stubbedev/newtab.html".text = ''
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <title>New Tab</title>
          <style>
            :root { color-scheme: dark; }
            html, body {
              margin: 0;
              height: 100%;
              background: #1e1e2e;
              color: #cdd6f4;
              font-family: ui-monospace, "JetBrains Mono", "SFMono-Regular", monospace;
            }
            body {
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              gap: 0.25rem;
            }
            #time { font-size: 5rem; font-weight: 600; letter-spacing: 0.04em; }
            #date { font-size: 1.2rem; color: #9399b2; }
          </style>
        </head>
        <body>
          <div id="time">--:--</div>
          <div id="date"></div>
          <script>
            function pad(n) { return String(n).padStart(2, "0"); }
            function tick() {
              var d = new Date();
              document.getElementById("time").textContent =
                pad(d.getHours()) + ":" + pad(d.getMinutes());
              document.getElementById("date").textContent =
                d.toLocaleDateString(undefined, {
                  weekday: "long", year: "numeric", month: "long", day: "numeric"
                });
            }
            tick();
            setInterval(tick, 1000);
          </script>
        </body>
        </html>
      '';
    };
}
