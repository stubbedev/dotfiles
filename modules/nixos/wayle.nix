{ inputs, ... }:
{
  # wayle is the xdg-desktop-portal backend on NixOS for Hyprland
  # (replaces xdg-desktop-portal-hyprland).
  # wayle implements every impl.portal interface natively; the upstream NixOS
  # module registers the system-level xdg.portal and the D-Bus-activated
  # xdg-desktop-portal-wayle user service. The bar itself still runs from the
  # HM wayle.service (modules/home/systemd.nix), so systemd.enable stays off.
  #
  # The HM-side equivalent for standalone (non-NixOS) home-manager lives in
  # modules/home/wayle-portal.nix; that one is gated to host.platform != "nixos"
  # so exactly one of the two owns the portal on any given host.
  flake.modules.nixos.wayle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hm = config.home-manager.users.${config.host.primaryUser}.features or { };
      enabled = (hm.wayle or false) && (hm.hyprland or false);
    in
    {
      # imports must be top-level and unconditional — nesting them inside
      # `lib.mkIf` makes the upstream module (and its options.programs.wayle)
      # vanish. The upstream module is inert until programs.wayle.enable, which
      # the gated config block below sets. Same shape as modules/nixos/sops.nix.
      imports = [ inputs.wayle.nixosModules.default ];

      config = lib.mkIf enabled {
        programs.wayle = {
          enable = true;
          # Native GL on NixOS, so the bare overlay package is correct here — the
          # HM-level nixGL wrap (modules/home/wayle.nix) is a passthrough on NixOS
          # anyway. This package backs the xdg-desktop-portal-wayle service.
          package = pkgs.wayle;
          # The shell (bar + notifications + OSD + wallpaper) runs from the HM
          # wayle.service; don't let the module spawn a second `wayle shell`.
          systemd.enable = false;
          # Register wayle + the xdg-desktop-portal-wayle service, enable
          # xdg.portal, and route common.default to wayle (mkDefault upstream).
          portal.enable = true;
          # Provision /etc/pam.d/wayle so the native ext-session-lock unlock can
          # authenticate (NixOS has no system-auth). Config sets
          # lock.pam-service = "wayle" (src/wayle/config.toml) to match.
          lock.enable = true;

          # No greeter here: login is greetd autologin straight into Hyprland
          # (modules/nixos/greetd.nix), so programs.wayle.greeter stays off.
        };

        # Route every interface to wayle. programs.hyprland registers its own
        # per-desktop portal section, and that section beats a plain
        # common.default = wayle for the Hyprland session. mkForce replaces the
        # whole config attr, dropping the per-desktop section so every session
        # falls through to this common block. wayle now implements every
        # impl.portal interface (Secret included), so no gnome-keyring carve-out
        # is needed; gnome/gtk stay only as dormant fallbacks.
        xdg.portal.config = lib.mkForce {
          common.default = [
            "wayle"
            "gnome"
            "gtk"
          ];
        };
      };
    };
}
