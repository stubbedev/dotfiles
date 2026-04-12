_: {
  moduleName = "activationSetupHyprSession";
  activationName = "setupHyprSession";
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, ... }:
    {
      promptTitle = "⚠️  SDDM Hyprland session entry missing";
      promptBody = ''
        SDDM needs a desktop entry to show Hyprland in the session menu.
        This will create the session entry for Hyprland (Nix).
      '';
      promptQuestion = "Create /usr/share/wayland-sessions/hyprland-nix.desktop?";
      actionScript = ''
        sudo mkdir -p /usr/share/wayland-sessions
        sudo tee /usr/share/wayland-sessions/hyprland-nix.desktop > /dev/null << 'EOF'
        [Desktop Entry]
        Name=Hyprland (Nix)
        Comment=Hyprland Wayland Compositor from Nix/Home Manager
        Exec=${config.home.homeDirectory}/.nix-profile/bin/start-hyprland
        Type=Application
        DesktopNames=Hyprland
        EOF
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
