_: {
  flake.modules.nixos.portal =
    { config, pkgs, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    {
      xdg.portal = {
        enable = true;
        # `programs.hyprland.enable` already adds its matching
        # xdg-desktop-portal-hyprland (same version as the Hyprland binary),
        # so we don't add it here — duplicating the package with a different
        # store path collides on the user-unit symlink farm. Same story for
        # `programs.niri.enable` and the Niri portal stack on niri-flake;
        # nixpkgs' niri pulls xdg-desktop-portal-gnome via xdg.portal.gtkUsePortal
        # automatically, so we only need to ensure GTK fallback is present.
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ]
        ++ lib.optionals (hmFeatures.hyprland or false) [
          xdg-desktop-portal-wlr
        ];
        config.common.default = "*";
      };
    };
}
