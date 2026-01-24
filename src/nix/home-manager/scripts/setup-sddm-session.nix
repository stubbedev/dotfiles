{ config, pkgs, lib, homeLib, ... }:

let
  desktopPath = "/usr/share/wayland-sessions/hyprland-nix.desktop";

  desktopContent = ''
    [Desktop Entry]
    Name=Hyprland (Nix)
    Comment=Hyprland Wayland Compositor from Nix/Home Manager
    Exec=${config.home.homeDirectory}/.nix-profile/bin/start-hyprland
    Type=Application
    DesktopNames=Hyprland
  '';

  setupScript = homeLib.sudoPromptScript {
    inherit pkgs;
    name = "setup-sddm-session";
    preCheck = ''
      if [ -f "${desktopPath}" ]; then
        if grep -Fxq "Exec=${config.home.homeDirectory}/.nix-profile/bin/start-hyprland" "${desktopPath}"; then
          exit 0
        fi
      fi
    '';
    promptTitle = "⚠️  SDDM Hyprland session entry missing";
    promptBody = ''
      echo "SDDM needs a desktop entry to show Hyprland in the session menu."
      echo "This will create the session entry for Hyprland (Nix)."
    '';
    promptQuestion = "Create ${desktopPath}?";
    actionScript = ''
      $SUDO mkdir -p /usr/share/wayland-sessions
      echo "${desktopContent}" | $SUDO tee "${desktopPath}" > /dev/null
      echo ""
      echo "✓ SDDM session entry created successfully!"
    '';
    skipMessage = "Skipped. You can create it later by running: home-manager switch --flake . --impure";
  };

in ''
  ${setupScript}
''
