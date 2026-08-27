_: {
  flake.modules.nixos.locale = _: {
    # Auto-detect timezone via geoclue2 / automatic-timezoned. The
    # service watches for location changes and updates /etc/localtime
    # without needing a hardcoded `time.timeZone`. Travel-friendly.
    services.geoclue2.enable = true;
    services.automatic-timezoned.enable = true;

    # American English UI strings, but British date/time formats
    # (DD/MM/YYYY, 24h). Split via LC_TIME so the rest of the locale
    # stays en_US (number/currency formats and most software defaults
    # are tested against it).
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
