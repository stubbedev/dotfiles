_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
        rm -rf "${config.home.homeDirectory}/.config/nvim"
        ln -sf "${config.home.homeDirectory}/.stubbe/src/nvim" "${config.home.homeDirectory}/.config/nvim"
      '';
    };
}
