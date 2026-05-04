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
        niri = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Niri-specific packages and configuration.";
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
        rust = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable rust toolchain installation";
        };
        srv = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable srv site management tool.";
        };
        php = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable php installation.";
        };
        k8s = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Kubernetes tools (kubectl, minikube).";
        };
        claudeCode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable claude-code CLI from nixpkgs unstable.";
        };
        browsers = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable web browsers (Firefox, Google Chrome).";
        };
        slack = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Slack desktop client.";
        };
      };
    };
}
