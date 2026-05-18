{ self, ... }:
{
  flake.modules.homeManager.xdgNiri =
    {
      config,
      constants,
      lib,
      homeLib,
      ...
    }:
    lib.mkIf config.features.niri {
      xdg.configFile =
        homeLib.xdgSources [
          "niri/hypridle.conf"
          "niri/scripts"
        ]
        // {
          # Render niri's config.kdl through Nix so cursor theme/size flow
          # from constants.theme. Source under src/niri/config.kdl uses
          # @XCURSOR_THEME@ / @XCURSOR_SIZE@ markers; substituteFile reads
          # the file and replaces them at HM build time.
          "niri/config.kdl" = {
            text = homeLib.substituteFile {
              file = self + "/src/niri/config.kdl";
              vars = {
                XCURSOR_THEME = constants.theme.cursor;
                XCURSOR_SIZE = toString constants.theme.cursorSize;
              };
            };
            force = true;
          };
        };
    };
}
