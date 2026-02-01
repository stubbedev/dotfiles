_: {
  flake.modules.homeManager.programsTmux =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      programs.tmux =
        let
          tmuxStubbe = pkgs.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-stubbe";
            rtpFilePath = "stubbe.tmux";
            version = "unstable-master";
            src = builtins.fetchGit {
              url = "https://github.com/stubbedev/tmux-stubbe";
              ref = "master";
            };
          };
        in
        {
          enable = true;
          sensibleOnTop = true;
          extraConfig = builtins.readFile ../../../../tmux/tmux.conf;
          plugins = with pkgs.tmuxPlugins; [
            yank
            resurrect
            continuum
            tmuxStubbe
          ];
        };
    };
}
