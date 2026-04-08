_: {
  flake.modules.homeManager.programsTmux =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file.".config/tmux/scripts/commands.sh" = {
        source = ../../../../tmux/scripts/commands.sh;
        executable = true;
      };

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        extraConfig = builtins.readFile ../../../../tmux/tmux.conf;
        plugins = with pkgs.tmuxPlugins; [
          yank
          resurrect
          continuum
        ];
      };
    };
}
