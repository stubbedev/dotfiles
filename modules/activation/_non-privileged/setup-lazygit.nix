_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    {
      config,
      pkgs,
      ...
    }:
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.config/lazygit"
        cat "${config.home.homeDirectory}/.stubbe/src/lazygit/state.yml" > "${config.home.homeDirectory}/.config/lazygit/state.yml"
        echo "lastversion: ${pkgs.lazygit.version}" >> "${config.home.homeDirectory}/.config/lazygit/state.yml"
      '';
    };
}
