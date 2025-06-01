{ config, pkgs, ... }:
{
  programs.git = {
      enable = true;
      userName = "Alexander Bugge Stage";
      userEmail = "abs@stubbe.dev";
      extraConfig = {
        core = {
          excludesfile = "~/.gitignore";
          editor = "nvim";
        };
        push.autoSetupRemote = true;
        advice.setUpstreamFailure = false;
      };
    };
}
