_: {
  flake.modules.nixos.pam =
    { lib, ... }:
    {
      security.pam.services = {
        # The session lock's PAM service (/etc/pam.d/wayle) is provisioned by the
        # wayle nixos module (programs.wayle.lock.enable, modules/nixos/wayle.nix),
        # since wayle locks natively via ext-session-lock-v1 on both compositors.

        # Enable GNOME keyring autounlock on both the tty-login and greetd PAM
        # stacks. greetd (the wayle greeter's display manager) authenticates the
        # graphical login under its own PAM service ("greetd"), not "login", so
        # both need the hook or the keyring stays locked after graphical login.
        login.enableGnomeKeyring = lib.mkDefault true;
        greetd.enableGnomeKeyring = true;
      };
    };
}
