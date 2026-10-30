_: {
  flake.modules.homeManager.git =
    {
      config,
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
            # New home upstream (was gui.authorColors); emitting the migrated
            # shape keeps lazygit from rewriting the read-only config.yml.
            authorColors."*" = c.lavender;
          };
        };
      };
    in
    {
      programs.git = {
        enable = true;
        ignores = [
          ".worktrees"
          ".treeman.yaml"
          ".treeman.local.yaml"
          ".treeman/"
          ".treeman-hooks/"
          ".pre-commit-config.yaml"
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

      home.packages = [ pkgs.gh ];

      # ~/.config/gh/hosts.yml carries the GitHub CLI oauth_token. By default gh
      # stashes the token in libsecret under "Default_Keyring", which PAM does
      # NOT auto-unlock — so the token effectively vanishes on every reboot.
      # Pinning hosts.yml through sops sidesteps the keyring entirely. It reuses
      # the github-token secret nix's access-tokens already read (see nix.nix),
      # so one token rotation covers both.
      sops.secrets.github-token = pkgs.stubbe.secret { name = "github-token"; };
      sops.templates."gh-hosts.yml" = {
        content = ''
          github.com:
              git_protocol: ssh
              users:
                  stubbedev:
                      oauth_token: ${config.sops.placeholder.github-token}
              user: stubbedev
              oauth_token: ${config.sops.placeholder.github-token}
        '';
        path = "${config.xdg.configHome}/gh/hosts.yml";
      };

      programs.lazygit = {
        enable = true;
        settings = lazygitSettings;
      };

      stubbe.mutable.".config/lazygit/state.yml" = {
        method = "copy";
        source = pkgs.stubbe.gen.yaml "lazygit-state.yml" {
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
