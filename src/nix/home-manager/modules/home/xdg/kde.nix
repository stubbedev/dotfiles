{ ... }:
{
  flake.modules.homeManager.xdgKde = { config, lib, ... }:
    lib.mkIf config.features.desktop {
      xdg.configFile = {
        # KDE Plasma Wayland configuration to use nixGL-wrapped Xwayland
        # This enables GLX support with NVIDIA drivers for X11 apps (like Steam)
        "kwinrc" = {
          text = lib.generators.toINI { } {
            Xwayland = {
              Scale = 1;
              ServerPath = "${config.home.homeDirectory}/.nix-profile/bin/Xwayland";
              XwaylandEavesdrops = "None";
            };
          };
          force = true;
        };
      };
    };
}
