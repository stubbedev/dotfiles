_: {
  flake.modules.homeManager.filesShell =
    {
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      # .zshrc/.zshenv are owned by programs.zsh (modules/home/zsh/zsh.nix).
      home.file = {
        ".ideavimrc".source = self + "/src/ideavim/ideavimrc";
        ".prettierrc.json".source = self + "/src/prettier/.prettierrc.json";
      };
    };
}
