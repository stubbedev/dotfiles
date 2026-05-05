_: {
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, homeLib, ... }:
    {
      promptTitle = "⚠️  SDDM Hyprland session entry missing";
      promptBody = ''
        SDDM needs a desktop entry to show Hyprland in the session menu.
        This will create the session entry for Hyprland (Nix).
      '';
      promptQuestion = "Create /usr/share/wayland-sessions/hyprland-nix.desktop?";
      actionScript = ''
        sudo install -d -m 0755 /usr/share/wayland-sessions
        ${homeLib.installSystemFile {
          target = "/usr/share/wayland-sessions/hyprland-nix.desktop";
          content = ''
            [Desktop Entry]
            Name=Hyprland (Nix)
            Comment=Hyprland Wayland Compositor from Nix/Home Manager
            Exec=${config.home.homeDirectory}/.nix-profile/bin/start-hyprland
            Type=Application
            DesktopNames=Hyprland
          '';
        }}
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
