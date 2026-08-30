_: {
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
