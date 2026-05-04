_: {
  flake.modules.homeManager.programsGit =
    {
      lib,
      config,
      pkgs,
      homeLib,
      ...
    }:
    lib.mkIf config.features.desktop (
      let
        stripClaudeCoauthorsHook = pkgs.writeShellScript "git-hook-commit-msg-strip-claude-coauthors" ''
          exec ${pkgs.gnused}/bin/sed -E -i '/^Co-authored-by:.*(Claude|Anthropic)/Id' "$1"
        '';
      in
      {
        xdg.configFile = homeLib.xdgSources [
          "git/ignore"
        ];
        programs.git = {
          enable = true;
          hooks = {
            commit-msg = stripClaudeCoauthorsHook;
          };
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
      }
    );
}
