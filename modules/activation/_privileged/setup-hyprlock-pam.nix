{ self, ... }:
{
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { homeLib, ... }:
    {
      promptTitle = "⚠️  Hyprlock PAM configuration missing";
      promptBody = ''
        Hyprlock needs a PAM configuration to authenticate passwords.
        This will create a minimal Nix-compatible PAM config.
      '';
      promptQuestion = "Create /etc/pam.d/hyprlock?";
      actionScript = homeLib.installSystemFile {
        target = "/etc/pam.d/hyprlock";
        content = builtins.readFile (self + "/src/pam.d/hyprlock");
      };
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
