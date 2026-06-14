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
    let
      # Does this machine have a battery? Read /sys impurely (the flake already
      # runs --impure; same pattern as nvidiaVersion in modules/overlays.nix).
      # Used to drop the battery module from the bar on desktops.
      hasBattery =
        let
          psu = /. + "/sys/class/power_supply";
        in
        builtins.pathExists psu
        && lib.any (lib.hasPrefix "BAT") (builtins.attrNames (builtins.readDir psu));
    in
    lib.mkIf (config.features.wayle && (config.features.hyprland || config.features.niri)) {
      home.packages = [
        (homeLib.gfx pkgs.wayle)
        # wayle's wallpaper engine shells out to awww (ships awww + awww-daemon);
        # without it `wayle wallpaper set` fails with "neither awww nor swww
        # found in PATH". This is why awww stays installed under wayle.
        (homeLib.gfx pkgs.awww)
        (homeLib.gfxExe "awww-daemon" pkgs.awww)
        # inotifywait — event-driven VPN widget (wayle-widget vpn-watch) waits
        # on the openconnect marker files instead of polling.
        pkgs.inotify-tools
      ];

      # Render config.toml (single file, NOT the whole ~/.config/wayle dir:
      # wayle writes into that dir at runtime, so symlinking the directory makes
      # HM fail with "cannot overwrite directory"). Templated so @BATTERY@
      # becomes the battery module only on machines that have one.
      xdg.configFile."wayle/config.toml" = {
        text = homeLib.substituteFile {
          file = self + "/src/wayle/config.toml";
          vars.BATTERY = if hasBattery then "\"battery\"," else "";
        };
        force = true;
      };

      # Populate the wayle icon theme. `wayle icons setup` can't run from a
      # nix build (it hardcodes RESOURCES_DIR to the build-sandbox path via
      # env!("CARGO_MANIFEST_DIR")), so replicate it: copy the bundled
      # symbolic SVGs from the package source into the user icon dir. Without
      # this, every module icon falls back to a grey circle. ~/.local/share/
      # wayle/icons is wayle-owned (not HM-symlinked), so copy at activation.
      home.activation.wayleIcons = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _wsrc="${pkgs.wayle.src}/resources/icons/hicolor/scalable/actions"
        _wdst="${config.xdg.dataHome}/wayle/icons"
        run mkdir -p "$_wdst/hicolor/scalable/actions"
        run install -m644 ${pkgs.writeText "wayle-icons-index.theme" ''
          [Icon Theme]
          Name=Wayle Icons
          Comment=Icons installed by Wayle
          Directories=hicolor/scalable/actions

          [hicolor/scalable/actions]
          Size=48
          MinSize=16
          MaxSize=512
          Type=Scalable
        ''} "$_wdst/index.theme"
        # --no-preserve=mode: store SVGs are read-only; copied files must stay
        # writable so the next activation can overwrite them.
        run cp -f --no-preserve=mode "$_wsrc"/*.svg "$_wdst/hicolor/scalable/actions/"
      '';
    };
}
