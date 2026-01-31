# greetd display manager and tuigreet greeter
_: {
  flake.modules.homeManager.packagesGreetd =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.greetd {
      home.packages = with pkgs; [
        greetd
        tuigreet
        terminus_font  # Console fonts for TTY (includes ter-132n and many others)
      ];
    };
}
