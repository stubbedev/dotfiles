_: {
  flake.modules.nixos.desktop =
    { ... }:
    {
      # HM-side modules/theme/dconf.nix writes dconf keys (color-scheme,
      # blueman). On NixOS, the dconf service must be enabled system-wide
      # for the HM dconf module to apply settings — otherwise activation
      # errors with "dconf is not enabled".
      programs.dconf.enable = true;

      # GTK applications consult xdg-desktop-portal for file pickers,
      # screen sharing, etc. portal.nix already enables the service; this
      # is the explicit GSettings dependency that pulls in the schema.
      services.gnome.gnome-keyring.enable = true;
    };
}
