_: {
  flake.modules.nixos.users =
    { config, ... }:
    {
      users.users.${config.host.primaryUser} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "video"
          "audio"
          "networkmanager"
          "i2c"
          "dialout"
        ];
      };
    };

  flake.modules.nixos.userDirs =
    { config, pkgs, ... }:
    let
      user = config.host.primaryUser;
      inherit (config.users.users.${user}) home group;
    in
    {
      systemd.tmpfiles.rules = map (dir: "d ${home}/${dir} 0755 ${user} ${group} - -") (
        [ "git" ] ++ pkgs.stubbe.repoDirs ++ [ "docs" ]
      );
    };

  flake.modules.nixos.locale = _: {
    services.geoclue2.enable = true;
    services.automatic-timezoned.enable = true;

    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocaleSettings = {
        LC_TIME = "en_GB.UTF-8";
      };
      supportedLocales = [
        "en_US.UTF-8/UTF-8"
        "en_GB.UTF-8/UTF-8"
      ];
    };

    console.keyMap = "us";
  };
}
