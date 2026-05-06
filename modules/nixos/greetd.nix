_: {
  flake.modules.nixos.greetd =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      hyprlandEnabled = hmFeatures.hyprland or false;

      # Mirrors the greeting/theme in src/greetd/config.toml. The non-NixOS
      # config hardcodes ~/.nix-profile/bin paths; on NixOS the Hyprland
      # session ships in /run/current-system/sw via programs.hyprland.enable,
      # so we point greetd at the binary directly.
      sessionCmd = if hyprlandEnabled then "Hyprland" else "${pkgs.bash}/bin/bash";
      tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
    in
    {
      services.greetd = {
        enable = true;
        settings = {
          terminal.vt = 1;
          default_session = {
            command = lib.concatStringsSep " " [
              tuigreet
              "--time --time-format '%F %R'"
              "--remember --remember-session --asterisks"
              "--theme 'border=magenta;text=white;prompt=blue;time=red;action=yellow;button=yellow;container=black;input=green;title=magenta;greet=cyan'"
              "--greeting 'Welcome to Hyprland'"
              "--cmd ${sessionCmd}"
            ];
            user = "greeter";
          };
        };
      };
    };
}
