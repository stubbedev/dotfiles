{ ... }:
{
  flake.modules.homeManager.packages.security = { pkgs, ... }: {
    home.packages = with pkgs; [
      # GPG and keyring tools
      gnupg
      pinentry-gnome3 # Wayland-compatible pinentry for GPG
      gcr_4 # GNOME Crypto library (provides gcr-prompter)
      libsecret # Secret storage library

      # Keyring management GUI
      seahorse # GNOME keyring manager
    ];
  };
}
