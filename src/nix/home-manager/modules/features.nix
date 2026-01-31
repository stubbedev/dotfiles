_: {
  flake.modules.homeManager.features =
    { lib, ... }:
    {
      options.features = {
        desktop = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable desktop UI packages and configuration.";
        };
        development = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable development tools and languages.";
        };
        hyprland = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Hyprland-specific packages and configuration.";
        };
        theming = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable theme packages and settings.";
        };
        media = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable media-related packages and config.";
        };
        vpn = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable VPN scripts and configuration.";
        };
        opencode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable opencode package and config.";
        };
        greetd = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable greetd display manager with tuigreet.";
        };
      };
    };
}
