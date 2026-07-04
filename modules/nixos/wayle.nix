{ inputs, ... }:
{
  # wayle is the xdg-desktop-portal backend on NixOS, for every compositor
  # (replaces xdg-desktop-portal-hyprland for Hyprland and -gnome for niri).
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
      enabled = (hm.wayle or false) && ((hm.hyprland or false) || (hm.niri or false));
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

          # Login screen: greetd + a cage-hosted wayle-greeter (replaces SDDM).
          # session.dirs defaults to the aggregate NixOS wayland-sessions dir, so
          # the picker lists every installed compositor — Hyprland AND niri here,
          # both register session files via programs.hyprland/programs.niri. The
          # greeter runs as the greetd user with no $HOME, so its theme comes
          # from /etc/wayle/config.toml, written from `settings` below. Only the
          # keys the greeter honours (font, styling palette, lock background +
          # clock) are set — the full shell config in src/wayle/config.toml is
          # the primary user's and unreadable here, so this is a themed subset
          # kept in sync with it (Catppuccin Mocha).
          greeter = {
            enable = true;
            # Force the greeter stack (cage/wlroots + GTK) onto its software
            # path. `auto` lets cage try GLES2 on nvidia, which crashes instead
            # of falling back — the greeter exits without creating a session and
            # greetd crash-loops to start-limit-hit (nothing ever renders). The
            # login screen needs no acceleration, so software is a safe, reliable
            # render path. The user session (Hyprland/niri) still uses the GPU.
            renderer = "software";
            settings = {
              general = {
                font-sans = "JetBrainsMono Nerd Font";
                font-mono = "JetBrainsMono Nerd Font";
              };
              styling = {
                theme-provider = "wayle";
                rounding = "sm";
                palette = {
                  bg = "#1e1e2e";
                  surface = "#181825";
                  elevated = "#313244";
                  fg = "#cdd6f4";
                  fg-muted = "#a6adc8";
                  primary = "#cba6f7";
                  red = "#f38ba8";
                  yellow = "#f9e2af";
                  green = "#a6e3a1";
                  blue = "#89b4fa";
                };
              };
              lock = {
                background-mode = "color";
                background-color = "#1e1e2e";
                date-format = "%A, %d %B %Y";
              };
            };
          };
        };

        # Route every interface to wayle under BOTH compositors. nixpkgs'
        # programs.niri pins `xdg.portal.config.niri.default = [ "gnome" "gtk" ]`
        # (and sends FileChooser/Notification/Access to gtk); programs.hyprland
        # registers its own section too. Those per-desktop sections beat the
        # common default for that session, so a plain common.default = wayle
        # would be ignored under niri. mkForce replaces the whole config attr,
        # dropping the per-desktop sections so every session falls through to
        # this common block. wayle now implements every impl.portal interface
        # (Secret included), so no gnome-keyring carve-out is needed; gnome/gtk
        # stay only as dormant fallbacks (still registered via programs.niri).
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
