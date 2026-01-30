{ ... }:
{
  flake.modules.homeManager.activation.restartWaybar = { lib, ... }:
    {
      home.activation.restartWaybar = lib.hm.dag.entryAfter [ "setupGrubIntelPstate" ] ''
        if command -v systemctl >/dev/null 2>&1; then
          $DRY_RUN_CMD systemctl --user restart waybar.service || true
        fi
      '';
    };
}
