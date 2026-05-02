_: {
  flake.modules.homeManager.packagesWaylandTools =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      enabled = config.features.hyprland || config.features.niri;
    in
    lib.mkIf enabled {
      home.packages = with pkgs; [
        # Screen locker (ext-session-lock-v1)
        (homeLib.gfx hyprlock)

        # Idle daemon (ext-idle-notify-v1)
        hypridle

        # Color temperature (wlr-gamma-control-v1)
        hyprsunset

        # Color picker (screencopy protocol)
        (homeLib.gfx hyprpicker)

        # Cursor theme tool
        hyprcursor

        # Polkit authentication agent (standard D-Bus polkit)
        hyprpolkitagent

        # Screenshot and region selection
        (homeLib.gfx grim)
        (homeLib.gfx slurp)

        # Wayland debug/inspection tools
        wlprop
        wayland-utils
      ];
    };
}
