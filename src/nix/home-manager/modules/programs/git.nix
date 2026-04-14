_: {
  flake.modules.homeManager.programsGit =
    {
      lib,
      config,
      pkgs,
      homeLib,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
        "git/ignore"
      ];
      programs.git = {
        enable = true;
        settings = {
          user = {
            name = "Alexander Bugge Stage";
            email = "abs@stubbe.dev";
          };
          core = {
            excludesfile = "~/.config/git/ignore";
            editor = "${pkgs.neovim}/bin/nvim";
          };
          init.defaultBranch = "master";
          push.autoSetupRemote = true;
          pull.rebase = false;
          advice.setUpstreamFailure = false;
        };
      };
    };
}
