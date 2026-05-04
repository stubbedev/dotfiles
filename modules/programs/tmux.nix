_: {
  flake.modules.homeManager.programsTmux =
    {
      self,
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file.".config/tmux/scripts/commands.sh" = {
        source = self + "/src/tmux/scripts/commands.sh";
        executable = true;
      };

      programs.tmux = {
        enable = true;
        sensibleOnTop = true;
        extraConfig = builtins.readFile (self + "/src/tmux/tmux.conf");
        plugins = with pkgs.tmuxPlugins; [
          yank
          resurrect
          continuum
        ];
      };
    };
}
