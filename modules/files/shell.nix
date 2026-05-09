_: {
  flake.modules.homeManager.filesShell =
    {
      constants,
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file = {
        # Ubuntu's /etc/zsh/zshrc runs compinit with the system-default
        # fpath, overwriting ~/.zcompdump before our init can extend
        # fpath with ~/.nix-profile/share/zsh/site-functions. Setting
        # this in .zshenv (sourced before /etc/zshrc) suppresses that
        # global compinit so our init.zsh produces the only dump.
        ".zshenv".text = ''
          skip_global_compinit=1
        '';
        ".zshrc".text = ''
          if [[ -f "${constants.paths.zsh}/init" ]]; then
            source ${constants.paths.zsh}/init
          fi
        '';
        ".ideavimrc".source = self + "/src/ideavim/ideavimrc";
        ".prettierrc.json".source = self + "/src/prettier/.prettierrc.json";
      };
    };
}
