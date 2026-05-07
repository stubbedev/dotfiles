_: {
  flake.modules.nixos.gnupg =
    { pkgs, ... }:
    {
      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-gnome3;
      };
    };
}
