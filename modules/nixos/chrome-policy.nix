_: {
  # NixOS counterpart of modules/activation/privileged/setup-chrome-policy.nix
  # (which is gated off on NixOS). Chrome reads enterprise policies from
  # /etc/opt/chrome/policies/managed/.
  flake.modules.nixos.chromePolicy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.browsers or false) {
      # Shared policy body (new-tab/homepage URL + force-installed
      # extensions) — see lib/chrome-policy.nix.
      environment.etc."opt/chrome/policies/managed/stubbedev-newtab.json".text = builtins.toJSON (
        import ../../lib/chrome-policy.nix {
          newtabUrl = pkgs.stubbe.newtabUrl;
        }
      );
    };
}
