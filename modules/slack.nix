_: {
  flake.modules.homeManager.slack =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.slack {
      home.packages = [
        (config.stubbe.gfx.bundle {
          pkg = pkgs.slack;
          flags = [ "--disable-setuid-sandbox" ];
        })
      ];

      stubbe.setup.slackApparmor = pkgs.stubbe.apparmorSetup {
        appName = "Slack";
        profileName = "nix-slack";
        programGlob = "/nix/store/*/lib/slack/{slack,chrome-sandbox}";
      };
    };
}
