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
        # mkWrappedPackage (not bare gfx): symlinkJoins the nixGL-wrapped
        # binaries back with the upstream package, so $out/share survives into
        # the profile. That puts wayle's bundled icons (share/icons/hicolor/
        # scalable/actions, 364 cm-*-symbolic SVGs) on XDG_DATA_DIRS, where
        # GTK's hicolor fallback resolves the from_icon_name() lookups — no
        # need to hand-populate ~/.local/share/wayle/icons. Also exposes the
        # wayle-settings .desktop entry. Both GTK4 binaries get the GL wrap.
        (homeLib.mkWrappedPackage {
          pkg = pkgs.wayle;
          exes = [
            "wayle"
            "wayle-settings"
          ];
        })
        # wayle's wallpaper engine shells out to awww (ships awww + awww-daemon);
        # without it `wayle wallpaper set` fails with "neither awww nor swww
        # found in PATH". This is why awww stays installed under wayle.
        (homeLib.gfx pkgs.awww)
        (homeLib.gfxExe "awww-daemon" pkgs.awww)
        # inotifywait — event-driven VPN widget (wayle-widget vpn-watch) waits
        # on the openconnect marker files instead of polling.
        pkgs.inotify-tools
        # brightnessctl — wayle has no brightness CLI, so the brightness
        # module's scroll actions (src/wayle/config.toml) shell out to it.
        pkgs.brightnessctl
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
    };
}
