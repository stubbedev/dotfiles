_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.config/btop"
        cat "${config.home.homeDirectory}/.stubbe/src/btop/btop.conf" > "${config.home.homeDirectory}/.config/btop/btop.conf"
      '';
    };
}
