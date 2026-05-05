{ self, ... }:
{
  enableIf = { config, ... }: config.features.hyprland;
  args = _:
    let
      pamConfig = builtins.readFile (self + "/src/pam.d/hyprlock");
    in
    {
      promptTitle = "⚠️  Hyprlock PAM configuration missing";
      promptBody = ''
        Hyprlock needs a PAM configuration to authenticate passwords.
        This will create a minimal Nix-compatible PAM config.
      '';
      promptQuestion = "Create /etc/pam.d/hyprlock?";
      actionScript = ''
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' EXIT
        cat > "$tmpfile" << 'EOF'
        ${pamConfig}EOF
        sudo install -m 0644 "$tmpfile" /etc/pam.d/hyprlock
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
