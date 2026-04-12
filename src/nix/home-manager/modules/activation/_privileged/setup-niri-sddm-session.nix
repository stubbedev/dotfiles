_: {
  moduleName = "activationSetupNiriSession";
  activationName = "setupNiriSession";
  enableIf = { config, ... }: config.features.niri;
  args =
    { config, ... }:
    {
      promptTitle = "⚠️  SDDM Niri session entry missing";
      promptBody = ''
        SDDM needs a desktop entry to show Niri in the session menu.
        This will create the session entry for Niri (Nix).
      '';
      promptQuestion = "Create /usr/share/wayland-sessions/niri-nix.desktop?";
      actionScript = ''
        sudo mkdir -p /usr/share/wayland-sessions
        sudo tee /usr/share/wayland-sessions/niri-nix.desktop > /dev/null << 'EOF'
        [Desktop Entry]
        Name=Niri (Nix)
        Comment=Niri Wayland Compositor from Nix/Home Manager
        Exec=${config.home.homeDirectory}/.nix-profile/bin/start-niri
        Type=Application
        DesktopNames=niri
        EOF
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
