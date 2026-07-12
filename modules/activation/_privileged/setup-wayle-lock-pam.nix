{ self, ... }:
{
  # Non-NixOS only (NixOS provisions /etc/pam.d/wayle via the wayle nixos
  # module). wayle's native ext-session-lock unlock authenticates against this
  # PAM service; src/wayle/config.toml sets lock.pam-service = "wayle" to match.
  # Both compositors lock via wayle, so gate on either.
  enableIf = { config, ... }: config.features.hyprland || config.features.niri;
  args =
    { homeLib, ... }:
    {
      promptTitle = "⚠️  Wayle lock PAM configuration missing";
      promptBody = ''
        Wayle's session lock needs a PAM configuration to authenticate the
        unlock. This will create a minimal Nix-compatible PAM config.
      '';
      actionScript = homeLib.installSystemFile {
        target = "/etc/pam.d/wayle";
        content = builtins.readFile (self + "/src/pam.d/wayle");
      };
    };
}
