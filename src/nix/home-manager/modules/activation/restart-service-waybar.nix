{ ... }:
let
  order = import ./_order.nix;
in
{
  flake.modules.homeManager.activationRestartServiceWaybar = { lib, config, ... }:
    lib.mkIf config.features.hyprland {
      home.activation.restartWaybar = lib.hm.dag.entryAfter order.after.restartWaybar ''
        if command -v systemctl >/dev/null 2>&1; then
          $DRY_RUN_CMD systemctl --user restart waybar.service || true
        fi
      '';
    };
}
