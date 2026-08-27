# git, plus lazygit as its TUI.
#
# Both configs are generated from Nix: lazygit's theme then draws from
# `pkgs.stubbe.colors` instead of carrying its own copy of the palette, and its
# runtime state file is seeded through `stubbe.mutable` because lazygit rewrites
# it in place.
_: {
  flake.modules.homeManager.git =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      c = pkgs.stubbe.withHash;

      # Claude Code adds a Co-authored-by trailer to commits it writes. We
      # don't want it in this repo's history, and settings.includeCoAuthoredBy
      # only covers the tool's own path — a hook catches every route.
      stripClaudeCoauthors = pkgs.writeShellScript "git-hook-commit-msg-strip-claude-coauthors" ''
        exec ${lib.getExe pkgs.gnused} -E -i '/^Co-authored-by:.*(Claude|Anthropic)/Id' "$1"
      '';

      lazygitSettings = {
        os = {
          edit = "nvim {{filename}}";
          editAtLine = "nvim +{{line}} {{filename}}";
          editAtLineAndWait = "nvim +{{line}} {{filename}}";
          editInTerminal = true;
        };
        disableStartupPopups = false;
        promptToReturnFromSubprocess = false;
        # Unbind lazygit's own commit prompt so `c` reaches the custom command
        # below instead.
        keybinding.files.commitChanges = "";
        customCommands = [
          {
            key = "c";
            context = "files";
            prompts = [
              {
                type = "input";
                title = "Add Commit Message";
                key = "Message";
              }
            ];
            # Prefix the message with the ticket id from the branch name, when
            # the branch carries one.
            command = ''git commit -m "$(git branch --show-current | awk 'match($0, /[A-Z]+-[0-9]+/) { printf "%s: ", substr($0, RSTART, RLENGTH) }'){{ .Form.Message }}"'';
            description = "Custom commit message";
          }
        ];
        gui = {
          border = "single";
          theme = {
            activeBorderColor = [
              c.lavender
              "bold"
            ];
            inactiveBorderColor = [ c.subtext0 ];
            optionsTextColor = [ c.blue ];
            selectedLineBgColor = [ c.surface0 ];
            cherryPickedCommitBgColor = [ c.surface1 ];
            cherryPickedCommitFgColor = [ c.lavender ];
            unstagedChangesColor = [ c.red ];
            defaultFgColor = [ c.text ];
            searchingActiveBorderColor = [ c.yellow ];
          };
          authorColors."*" = c.lavender;
        };
      };
    in
    lib.mkIf config.features.desktop {
      programs.git = {
        enable = true;
        hooks.commit-msg = stripClaudeCoauthors;
        settings = {
          user = {
            name = "Alexander Bugge Stage";
            email = "abs@stubbe.dev";
          };
          core.excludesfile = "~/.config/git/ignore";
          # Cache untracked-file enumeration per directory (keyed on mtime) so
          # `git status` skips re-walking unchanged trees — the big gitignored
          # vendor/ and node_modules/ dirs in large checkouts. Takes a cold
          # `git status` on the work monorepo from ~0.2s to ~0.01s, which is
          # what made the per-worktree scan in gwt/gwtd slow. Auto-maintained
          # by git; safe on local filesystems with reliable mtime.
          core.untrackedCache = true;
          # Large-repo index bundle: index v4 (smaller, faster to read) plus
          # index.skipHash (skip the trailing SHA on index writes). Also
          # implies core.untrackedCache — kept explicit above so the reason is
          # documented and survives a change to the feature bundle.
          feature.manyFiles = true;
          init.defaultBranch = "master";
          push.autoSetupRemote = true;
          pull.rebase = false;
          advice.setUpstreamFailure = false;
        };
      };

      programs.lazygit = {
        enable = true;
        settings = lazygitSettings;
      };

      xdg.configFile."git/ignore".source = pkgs.stubbe.file "src/git/ignore";

      # lazygit rewrites state.yml as you use it, so it cannot be a store
      # symlink. `lastversion` pins the current package version so lazygit's
      # "new version available" popup stays quiet after a nixpkgs bump.
      stubbe.mutable.".config/lazygit/state.yml" = {
        method = "copy";
        text = ''
          lastupdatecheck: 0
          startuppopupversion: 5
          customcommandshistory: []
          hidecommandlog: false
          ignorewhitespaceindiffview: true
          diffcontextsize: 3
          renamesimilaritythreshold: 50
          localbranchsortorder: recency
          remotebranchsortorder: alphabetical
          gitlogorder: topo-order
          gitlogshowgraph: always
          lastversion: ${pkgs.lazygit.version}
        '';
      };
    };
}
