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
