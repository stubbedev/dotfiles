_: {
  # wayle: Rust/GTK4 Wayland desktop shell that replaces the
  # waybar + swaync + hyprpaper/awww stack. Packaged in modules/overlays.nix
  # as pkgs.wayle. The systemd unit lives in modules/home/systemd.nix
  # alongside the legacy bar (shares compositorTargets + the await-* hooks);
  # this module only ships the package and symlinks the config.
  #
  # linuxOnly: GTK4 GL needs the nixGL wrap, same as waybar.
  linuxOnlyHomeModules.wayle =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf (config.features.wayle && (config.features.hyprland || config.features.niri)) {
      home.packages = [ (homeLib.gfx pkgs.wayle) ];

      # Symlinks src/wayle → ~/.config/wayle. Read-only store path, so the
      # wayle-settings GUI can't write back — config is declarative here.
      # The wallpaper (home-dir path) is applied at startup by wayle-launch,
      # not baked here, so no @HOME@ templating is needed.
      xdg.configFile = homeLib.xdgSource "wayle" { };
    };
}
