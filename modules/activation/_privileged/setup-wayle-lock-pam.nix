{ self, ... }:
{
  # Non-NixOS only (NixOS provisions /etc/pam.d/wayle via the wayle nixos
  # module). wayle's native ext-session-lock unlock authenticates against this
  # PAM service; src/wayle/config.toml sets lock.pam-service = "wayle" to match.
  # Both compositors lock via wayle, so gate on either.
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, homeLib, ... }:
    {
      promptTitle = "⚠️  Wayle lock PAM configuration missing";
      promptBody = ''
        Wayle's session lock needs a PAM configuration to authenticate the
        unlock. This will create a minimal Nix-compatible PAM config that also
        unlocks the login keyring on unlock.
      '';
      actionScript = ''
        ${homeLib.installSystemFile {
          target = "/etc/pam.d/wayle";
          # pam_gnome_keyring.so must be the nix-built module by absolute
          # path (see comment in src/pam.d/wayle); the ~/.nix-profile path
          # is stable, so the rendered file only changes when the src
          # template does.
          content =
            builtins.replaceStrings [ "@PAM_GNOME_KEYRING@" ]
              [ "${config.home.homeDirectory}/.nix-profile/lib/security/pam_gnome_keyring.so" ]
              (builtins.readFile (self + "/src/pam.d/wayle"));
        }}
      '';
    };
}
