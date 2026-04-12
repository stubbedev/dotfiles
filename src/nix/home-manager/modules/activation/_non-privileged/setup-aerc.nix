_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.config/aerc"
        rm -rf "${config.home.homeDirectory}/.config/aerc/stylesets"
        ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/stylesets" "${config.home.homeDirectory}/.config/aerc/stylesets"
        rm -rf "${config.home.homeDirectory}/.config/aerc/accounts"
        ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/accounts" "${config.home.homeDirectory}/.config/aerc/accounts"
        rm -rf "${config.home.homeDirectory}/.config/aerc/accounts.conf"
        ln -s "${config.home.homeDirectory}/.stubbe/src/aerc/accounts.conf" "${config.home.homeDirectory}/.config/aerc/accounts.conf"
        chmod 600 "${config.home.homeDirectory}/.stubbe/src/aerc/accounts.conf"
      '';
    };
}
