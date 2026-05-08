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

      # Enable GNOME keyring autounlock on both the login and SDDM PAM stacks.
      # SDDM uses its own PAM service ("sddm"), not "login", so both need the
      # hook or the keyring stays locked after graphical login.
      security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;
      security.pam.services.sddm.enableGnomeKeyring = true;
    };
}
