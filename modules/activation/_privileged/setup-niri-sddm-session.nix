_: {
  enableIf = { config, ... }: config.features.niri;
  args =
    { config, homeLib, ... }:
    {
      promptTitle = "⚠️  SDDM Niri session entry missing";
      promptBody = ''
        SDDM needs a desktop entry to show Niri in the session menu.
        This will create the session entry for Niri (Nix).
      '';
      promptQuestion = "Create /usr/share/wayland-sessions/niri-nix.desktop?";
      actionScript = ''
        sudo install -d -m 0755 /usr/share/wayland-sessions
        ${homeLib.installSystemFile {
          target = "/usr/share/wayland-sessions/niri-nix.desktop";
          content = ''
            [Desktop Entry]
            Name=Niri (Nix)
            Comment=Niri Wayland Compositor from Nix/Home Manager
            Exec=${config.home.homeDirectory}/.nix-profile/bin/start-niri
            Type=Application
            DesktopNames=niri
            X-GDM-SessionRegisters=true
          '';
        }}
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
