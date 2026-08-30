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

      lazygitSettings = {
        os = {
          edit = "nvim {{filename}}";
          editAtLine = "nvim +{{line}} {{filename}}";
          editAtLineAndWait = "nvim +{{line}} {{filename}}";
          editInTerminal = true;
        };
        disableStartupPopups = false;
        promptToReturnFromSubprocess = false;
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
        ignores = [
          ".worktrees"
          ".treeman.yaml"
          ".treeman.local.yaml"
          ".treeman/"
          ".treeman-hooks/"
          ".envrc"
          ".direnv/"
        ];
        settings = {
          user = {
            name = "Alexander Bugge Stage";
            email = "abs@stubbe.dev";
          };
          core.untrackedCache = true;
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

      stubbe.mutable.".config/lazygit/state.yml" = {
        method = "copy";
        source = (pkgs.formats.yaml { }).generate "lazygit-state.yml" {
          lastupdatecheck = 0;
          startuppopupversion = 5;
          customcommandshistory = [ ];
          hidecommandlog = false;
          ignorewhitespaceindiffview = true;
          diffcontextsize = 3;
          renamesimilaritythreshold = 50;
          localbranchsortorder = "recency";
          remotebranchsortorder = "alphabetical";
          gitlogorder = "topo-order";
          gitlogshowgraph = "always";
          lastversion = pkgs.lazygit.version;
        };
      };
    };
}
