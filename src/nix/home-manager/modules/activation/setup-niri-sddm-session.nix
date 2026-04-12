_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupNiriSession";
  activationName = "setupNiriSession";
  scriptName = "setup-niri-sddm-session";
  after = order.after.setupNiriSession;
  enableIf = { config, ... }: config.features.niri;
  sudoArgs =
    { config, ... }:
    let
      desktopPath = "/usr/share/wayland-sessions/niri-nix.desktop";

      desktopContent = ''
        [Desktop Entry]
        Name=Niri (Nix)
        Comment=Niri Wayland Compositor from Nix/Home Manager
        Exec=${config.home.homeDirectory}/.nix-profile/bin/start-niri
        Type=Application
        DesktopNames=niri
      '';
    in
    {
      preCheck = ''
        if [ -f "${desktopPath}" ]; then
          if grep -Fxq "Exec=${config.home.homeDirectory}/.nix-profile/bin/start-niri" "${desktopPath}"; then
            exit 0
          fi
        fi
      '';
      promptTitle = "⚠️  SDDM Niri session entry missing";
      promptBody = ''
        echo "SDDM needs a desktop entry to show Niri in the session menu."
        echo "This will create the session entry for Niri (Nix)."
      '';
      promptQuestion = "Create ${desktopPath}?";
      actionScript = ''
        sudo mkdir -p /usr/share/wayland-sessions
        echo "${desktopContent}" | sudo tee "${desktopPath}" > /dev/null
        echo ""
        echo "✓ SDDM Niri session entry created successfully!"
      '';
      skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
    };
}
