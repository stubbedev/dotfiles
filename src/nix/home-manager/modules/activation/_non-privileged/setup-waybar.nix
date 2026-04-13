_: {
  enableIf = { config, ... }: config.features.hyprland;
  args = _: {
    actionScript = ''
      if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet hyprland-session.target 2>/dev/null; then
          systemctl --user restart waybar.service || true
        fi
      fi
    '';
  };
}
