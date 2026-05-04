_: {
  flake.modules.nixos.pam =
    { lib, ... }:
    {
      # Hyprlock authenticates passwords against PAM. NixOS's default PAM
      # service set doesn't include hyprlock, so we declare it explicitly.
      security.pam.services.hyprlock = { };

      # Enable GNOME keyring autounlock on login session managers.
      # The non-NixOS activation scripts append pam_gnome_keyring.so
      # lines to /etc/pam.d/{login,sddm,...}; on NixOS this is a flag.
      security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;
      security.pam.services.sddm.enableGnomeKeyring = lib.mkDefault true;
      security.pam.services.gdm-password.enableGnomeKeyring = lib.mkDefault true;
    };
}
