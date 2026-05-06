_: {
  flake.modules.nixos.portal =
    { config, pkgs, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    {
      xdg.portal = {
        enable = true;
        # The Hyprland and wlr backends serve the wayland session;
        # GTK provides file-picker fallback. Gnome portal joins when
        # Niri is enabled (Niri's preferred interface).
        extraPortals = with pkgs;
          [
            xdg-desktop-portal-gtk
          ]
          ++ lib.optionals (hmFeatures.hyprland or false) [
            xdg-desktop-portal-hyprland
            xdg-desktop-portal-wlr
          ]
          ++ lib.optionals (hmFeatures.niri or false) [
            xdg-desktop-portal-gnome
          ];
        config.common.default = "*";
      };
    };
}
