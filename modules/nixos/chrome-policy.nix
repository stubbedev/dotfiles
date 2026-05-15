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
      # Shared policy body (new-tab/homepage URLs + force-installed
      # extensions) — see modules/packages/chrome/_policy.nix.
      environment.etc."opt/chrome/policies/managed/stubbedev-newtab.json".text =
        builtins.toJSON (import ../packages/chrome/_policy.nix { inherit newtabUrl; });
    };
}
