_: {
  linuxOnlyHomeModules.packagesHyprlandTools =
    {
      pkgs,
      homeLib,
      hyprland-guiutils,
      lib,
      config,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      guiutils = hyprland-guiutils.packages.${system}.default;
    in
    lib.mkIf config.features.hyprland {
      # hyprpaper dropped — wayle renders the wallpaper (via awww).
      home.packages = with pkgs; [
        (homeLib.gfxExe "hyprland-guiutils" guiutils)
        hyprshot
        hyprlang
        hyprkeys
        hyprtoolkit
        hyprlauncher
        hyprutils
        hyprprop
        hyprsysteminfo # might need wrapping
        hyprwayland-scanner
        hyprpwcenter # might need wrapping
      ];
    };
}
