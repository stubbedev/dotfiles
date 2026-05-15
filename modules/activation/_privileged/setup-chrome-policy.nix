_: {
  enableIf = { config, ... }: config.features.browsers;
  args =
    { homeLib, config, ... }:
    let
      newtabUrl = "file://${config.xdg.dataHome}/stubbedev/newtab.html";
      # Shared policy body (new-tab/homepage URLs + force-installed
      # extensions) — see modules/packages/chrome/_policy.nix.
      policy = import ../../packages/chrome/_policy.nix { inherit newtabUrl; };
    in
    homeLib.mkInstallPrompt {
      subject = "Chrome new-tab policy";
      body = ''
        Drop a Chrome enterprise policy at
        /etc/opt/chrome/policies/managed/stubbedev-newtab.json. It points
        the new tab page, new windows and the homepage at the minimal
        local page ~/.local/share/stubbedev/newtab.html, and force-installs
        the managed extensions (SurfingKeys, Bitwarden, React DevTools, …).

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
