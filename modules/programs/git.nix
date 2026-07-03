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
            core.excludesfile = "~/.config/git/ignore";
            # Cache untracked-file enumeration per directory (keyed on mtime) so
            # `git status` skips re-walking unchanged trees — the big gitignored
            # vendor/ + node_modules/ dirs in large checkouts. Turns a cold
            # `git status` on kontainer from ~0.2s to ~0.01s, which is what makes
            # the per-worktree scan in gwt/gwtd slow. Auto-maintained by git;
            # safe on local filesystems with reliable mtime (ext4/btrfs).
            core.untrackedCache = true;
            init.defaultBranch = "master";
            push.autoSetupRemote = true;
            pull.rebase = false;
            advice.setUpstreamFailure = false;
          };
        };
      }
    );
}
