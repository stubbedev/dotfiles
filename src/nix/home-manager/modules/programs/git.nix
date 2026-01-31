_: {
  flake.modules.homeManager.programsGit =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      programs.git = {
        enable = true;
        settings = {
          user = {
            name = "Alexander Bugge Stage";
            email = "abs@stubbe.dev";
          };
          core = {
            excludesfile = "~/.gitignore";
            editor = "nvim";
          };
          init.defaultBranch = "master";
          push.autoSetupRemote = true;
          advice.setUpstreamFailure = false;
        };
      };
    };
}
