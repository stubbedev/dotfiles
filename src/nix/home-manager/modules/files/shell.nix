{ ... }:
{
  flake.modules.homeManager.filesShell = { constants, lib, config, ... }:
    lib.mkIf config.features.desktop {
      home.file = {
        ".zshrc".text = ''
          if [[ -f "${constants.paths.zsh}/init" ]]; then
            source ${constants.paths.zsh}/init
          fi
        '';
        ".ideavimrc".source = ../../../../ideavim/ideavimrc;
        ".tmux.conf".source = ../../../../tmux/tmux.conf;
      };
    };
}
