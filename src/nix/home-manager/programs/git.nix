{ ... }: {
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Alexander Bugge Stage";
        email = "alexander.bugge.stage@gmail.com";
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
