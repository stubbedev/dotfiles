_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.config/aerc"
        rm -rf "${config.home.homeDirectory}/.config/aerc/stylesets"
        ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/stylesets" "${config.home.homeDirectory}/.config/aerc/stylesets"
      '';
    };
}
