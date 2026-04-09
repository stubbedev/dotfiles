_: {
  flake.modules.homeManager.programsGit = { lib, config, pkgs, ... }:
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
