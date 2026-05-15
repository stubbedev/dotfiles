_: {
  enableIf = { config, ... }: config.features.browsers;
  args =
    { homeLib, config, ... }:
    let
      newtabUrl = "file://${config.xdg.dataHome}/stubbedev/newtab.html";
      # NewTabPageLocation drives both the new tab page and new windows
      # (a new window opens a new tab page). HomepageLocation points the
      # home page / home button at the same minimal local page.
      policy = {
        NewTabPageLocation = newtabUrl;
        HomepageLocation = newtabUrl;
        HomepageIsNewTabPage = false;
      };
    in
    homeLib.mkInstallPrompt {
      subject = "Chrome new-tab policy";
      body = ''
        Drop a Chrome enterprise policy at
        /etc/opt/chrome/policies/managed/stubbedev-newtab.json so the new
        tab page, new windows and the homepage open the minimal local
        page at ~/.local/share/stubbedev/newtab.html. That lets SurfingKeys
        inject its content script without the "can't run here" banner.

        On NixOS this file is owned by modules/nixos/chrome-policy.nix and
        this activation is gated off.
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/opt/chrome/policies/managed
        ${homeLib.installSystemFile {
          target = "/etc/opt/chrome/policies/managed/stubbedev-newtab.json";
          content = builtins.toJSON policy + "\n";
        }}
      '';
    };
}
