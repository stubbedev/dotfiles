_: {
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
