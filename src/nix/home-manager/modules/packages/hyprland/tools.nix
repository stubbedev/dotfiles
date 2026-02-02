_: {
  flake.modules.homeManager.packagesHyprlandTools =
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
      home.packages = with pkgs; [
        (homeLib.gfx hyprlock)
        (homeLib.gfxExe "hyprland-guiutils" guiutils)
        hyprshot
        hyprlang
        hyprkeys
        hypridle
        (homeLib.gfx hyprpaper)
        hyprsunset
        (homeLib.gfx hyprpicker)
        hyprcursor
        hyprpolkitagent
        hyprutils
        hyprprop
        (homeLib.gfx hyprsysteminfo)
        hyprwayland-scanner
      ];
    };
}
