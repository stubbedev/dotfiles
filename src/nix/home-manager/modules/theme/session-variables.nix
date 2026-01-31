_: {
  flake.modules.homeManager.themeSessionVariables =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      home.sessionVariables = {
        GTK_THEME_VARIANT = "dark";
      };
    };
}
