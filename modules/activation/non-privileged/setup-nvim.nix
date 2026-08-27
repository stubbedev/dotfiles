_:

{
  flake.modules.homeManager.setupNvim = (import ../../../lib/activation-setups.nix).mkSetupModule (
    {
      name = "setupNvim";
    }
    // {
      enableIf =
        { config, ... }:
        config.features.desktop;
      args =
        { config, homeLib, ... }:
        {
          actionScript = homeLib.mkLiveSymlink {
            inherit config;
            src = "nvim";
            target = ".config/nvim";
          };
        };
    }
  );
}
