_: {
  flake.modules.nixos.pam =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      anyCompositor = (hmFeatures.hyprland or false) || (hmFeatures.niri or false);
    in
    {
      # Hyprlock authenticates passwords against PAM. NixOS's default PAM
      # service set doesn't include hyprlock, so declare it explicitly
      # whenever a wayland compositor we ship hyprlock under is enabled
      # (we use hyprlock as the lockscreen on both Hyprland and Niri).
      security.pam.services.hyprlock = lib.mkIf anyCompositor { };

      # Enable GNOME keyring autounlock on the login PAM stack. greetd
      # delegates to it, so this covers password unlock on console login
      # too. SDDM/GDM lines from the previous version dropped — we don't
      # ship those display managers on NixOS.
      security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;
    };
}
