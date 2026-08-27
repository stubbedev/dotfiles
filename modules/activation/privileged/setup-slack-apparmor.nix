_:

{
  flake.modules.homeManager.setupSlackApparmor =
    (import ../../../lib/activation-setups.nix).mkSudoSetupModule
      (
        {
          name = "setupSlackApparmor";
        }
        // {
          enableIf = { config, ... }: config.features.slack;
          args =
            { homeLib, ... }:
            homeLib.mkAppArmorSetup {
              appName = "Slack";
              profileName = "nix-slack";
              programGlob = "/nix/store/*/lib/slack/{slack,chrome-sandbox}";
              managedBy = "home-manager slack-apparmor v1";
            };
        }
      );
}
