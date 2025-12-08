{ ... }: {
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
      push.autoSetupRemote = true;
      advice.setUpstreamFailure = false;
    };
  };
}
