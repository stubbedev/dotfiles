_: {
  # NixOS counterpart of modules/activation/_privileged/setup-chrome-policy.nix
  # (which is gated off on NixOS). Chrome reads enterprise policies from
  # /etc/opt/chrome/policies/managed/.
  flake.modules.nixos.chromePolicy =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      userHome = config.users.users.${config.host.primaryUser}.home;
      newtabUrl = "file://${userHome}/.local/share/stubbedev/newtab.html";
    in
    lib.mkIf (hmFeatures.browsers or false) {
      # NewTabPageLocation drives both the new tab page and new windows
      # (a new window opens a new tab page). HomepageLocation points the
      # home page / home button at the same minimal local page.
      environment.etc."opt/chrome/policies/managed/stubbedev-newtab.json".text =
        builtins.toJSON {
          NewTabPageLocation = newtabUrl;
          HomepageLocation = newtabUrl;
          HomepageIsNewTabPage = false;
        };
    };
}
