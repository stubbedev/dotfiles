# CLI mail and TUI helpers
{ ... }:
{
  flake.modules.homeManager.packagesCliMail = { pkgs, lib, config, ... }:
    lib.mkIf config.features.desktop {
      home.packages = with pkgs; [
        msmtp
        w3m
        pandoc
        elinks
        lynx
        chafa
        catimg
      ];
    };
}
