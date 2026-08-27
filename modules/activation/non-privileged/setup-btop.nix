_:

{
  flake.modules.homeManager.setupBtop = (import ../../../lib/activation-setups.nix).mkSetupModule (
    {
      name = "setupBtop";
    }
    // {
      enableIf = { config, ... }: config.features.desktop;
      args =
        { config, homeLib, ... }:
        {
          actionScript = homeLib.mkLiveCopy {
            inherit config;
            src = "btop/btop.conf";
            target = ".config/btop/btop.conf";
          };
        };
    }
  );
}
