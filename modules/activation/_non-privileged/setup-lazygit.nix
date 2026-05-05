_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    {
      config,
      pkgs,
      homeLib,
      ...
    }:
    {
      # state.yml is rewritten by lazygit at runtime — copy on switch
      # instead of symlinking, then append the current pkg version so
      # lazygit's "new version" prompt knows we're up to date.
      actionScript = ''
        ${homeLib.mkLiveCopy {
          inherit config;
          src = "lazygit/state.yml";
          target = ".config/lazygit/state.yml";
        }}
        echo "lastversion: ${pkgs.lazygit.version}" >> "${config.home.homeDirectory}/.config/lazygit/state.yml"
      '';
    };
}
