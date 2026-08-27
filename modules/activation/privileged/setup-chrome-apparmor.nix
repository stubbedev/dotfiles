_:

{
  flake.modules.homeManager.setupChromeApparmor =
    (import ../../../lib/activation-setups.nix).mkSudoSetupModule
      (
        {
          name = "setupChromeApparmor";
        }
        // {
          enableIf = { config, ... }: config.features.browsers;
          args =
            { homeLib, ... }:
            homeLib.mkAppArmorSetup {
              appName = "Chrome";
              profileName = "nix-google-chrome-stable";
              programGlob = "/nix/store/*/share/google/chrome/{chrome,chrome-sandbox}";
              managedBy = "home-manager chrome-apparmor v1";
            };
        }
      );
}
