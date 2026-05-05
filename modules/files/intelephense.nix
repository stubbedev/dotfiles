_: {
  flake.modules.homeManager.filesIntelephense =
    {
      config,
      homeLib,
      ...
    }:
    {
      # secrets/intelephense holds the licence string verbatim.
      # Edit with: hm secret edit intelephense
      sops.secrets.intelephense_license = homeLib.mkBinarySecret {
        name = "intelephense";
        path = "${config.home.homeDirectory}/intelephense/license.txt";
      };
    };
}
