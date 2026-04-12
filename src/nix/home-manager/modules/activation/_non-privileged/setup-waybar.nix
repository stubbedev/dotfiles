_: {
  moduleName = "activationRestartServiceWaybar";
  activationName = "restartWaybar";
  enableIf = { config, ... }: config.features.hyprland;
  args = _: {
    actionScript = ''
      if command -v systemctl >/dev/null 2>&1; then
        systemctl --user restart waybar.service || true
      fi
    '';
  };
}
