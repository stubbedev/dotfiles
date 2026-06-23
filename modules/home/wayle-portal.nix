{ inputs, ... }:
{
  # Standalone (non-NixOS) home-manager: register wayle as the
  # xdg-desktop-portal backend at the user level — the .portal interface
  # declaration, the D-Bus activation file, a generic portals.conf routing
  # every interface to wayle, and the xdg-desktop-portal-wayle user service.
  #
  # On NixOS the system module (modules/nixos/wayle.nix) owns the portal
  # instead, so this is gated to host.platform != "nixos" to avoid registering
  # the backend twice. The upstream module is imported unconditionally (imports
  # can't be gated on config), but every effect lives behind `enable`, which is
  # off here on NixOS — so it stays inert there.
  flake.modules.homeManager.waylePortal =
    {
      config,
      lib,
      pkgs,
      homeLib,
      ...
    }:
    let
      enabled =
        config.features.wayle
        && (config.features.hyprland || config.features.niri)
        && config.host.platform != "nixos";
    in
    {
      imports = [ inputs.wayle.homeManagerModules.default ];

      programs.wayle = lib.mkIf enabled {
        enable = true;
        # GTK4 portal dialogs (file chooser, app chooser, …) need the nixGL wrap
        # off-NixOS to find EGL/GL drivers — same wrapped package the bar uses
        # (modules/home/wayle.nix). Identical derivation, so home-manager's
        # profile dedupes the two home.packages entries.
        package = homeLib.mkWrappedPackage {
          pkg = pkgs.wayle;
          exes = [
            "wayle"
            "wayle-settings"
          ];
        };
        # The shell runs from the HM wayle.service (modules/home/systemd.nix);
        # this module adds only the portal.
        systemd.enable = false;
        # config.toml is rendered (and @BATTERY@-templated) by
        # modules/home/wayle.nix — leave settings empty so the module doesn't
        # also write it.
        settings = { };
        portal.enable = true;
      };
    };
}
