_: {
  flake.modules.nixos.pam =
    { lib, ... }:
    {
      security.pam.services = {
        # The session lock's PAM service (/etc/pam.d/wayle) is provisioned by the
        # wayle nixos module (programs.wayle.lock.enable, modules/nixos/wayle.nix)
        # as `security.pam.services.wayle = {}`, since wayle locks natively via
        # ext-session-lock-v1 on both compositors. We merge enableGnomeKeyring in
        # here: login is greetd *autologin* (no password entered), so the keyring
        # never PAM-unlocks at boot — the wayle unlock is the only place the login
        # password is typed, so it's the gate that must unlock the keyring, or
        # secret-service clients (Chrome) prompt on first use each session.
        wayle.enableGnomeKeyring = true;

        # Enable GNOME keyring autounlock on both the tty-login and greetd PAM
        # stacks. greetd (autologin into Hyprland, modules/nixos/greetd.nix)
        # authenticates the graphical login under its own PAM service
        # ("greetd"), not "login", so both need the hook or the keyring stays
        # locked after graphical login.
        login.enableGnomeKeyring = lib.mkDefault true;
        greetd.enableGnomeKeyring = true;
      };
    };
}
