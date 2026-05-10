_: {
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
