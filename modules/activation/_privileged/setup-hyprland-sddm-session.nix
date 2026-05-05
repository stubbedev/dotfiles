_: {
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, homeLib, ... }:
    homeLib.mkSddmSession {
      inherit config;
      name = "hyprland-nix";
      displayName = "Hyprland (Nix)";
      comment = "Hyprland Wayland Compositor from Nix/Home Manager";
      execName = "start-hyprland";
      desktopNames = "Hyprland";
    };
}
