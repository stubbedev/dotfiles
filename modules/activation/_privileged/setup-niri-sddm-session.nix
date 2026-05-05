_: {
  enableIf = { config, ... }: config.features.niri;
  args =
    { config, homeLib, ... }:
    homeLib.mkSddmSession {
      inherit config;
      name = "niri-nix";
      displayName = "Niri (Nix)";
      comment = "Niri Wayland Compositor from Nix/Home Manager";
      execName = "start-niri";
      desktopNames = "niri";
      extraEntries.X-GDM-SessionRegisters = "true";
    };
}
