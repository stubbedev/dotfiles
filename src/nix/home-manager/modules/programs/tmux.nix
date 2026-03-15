_: {
  flake.modules.homeManager.programsTmux =
    {
      lib,
      config,
      pkgs,
      tmux-stubbe,
      ...
    }:
    lib.mkIf config.features.desktop {
      programs.tmux =
        let
          tmuxStubbe = pkgs.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-stubbe";
            rtpFilePath = "stubbe.tmux";
            version = "unstable-master";
            src = tmux-stubbe;
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
