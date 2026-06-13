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
      self,
      ...
    }:
    lib.mkIf (config.features.wayle && (config.features.hyprland || config.features.niri)) {
      home.packages = [ (homeLib.gfx pkgs.wayle) ];

      # Render config.toml with @HOME@ substituted (wayle does not expand ~ in
      # the wallpaper path). Read-only store path, so the wayle-settings GUI
      # can't write back — config is declarative here.
      xdg.configFile."wayle/config.toml" = {
        text = homeLib.substituteFile {
          file = self + "/src/wayle/config.toml";
          vars.HOME = config.home.homeDirectory;
        };
        force = true;
      };
    };
}
