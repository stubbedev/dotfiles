_: {
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { ... }:
    {
      # Reload Hyprland after every successful home-manager switch when a live
      # Hyprland session is detected. Skipped silently otherwise (e.g. running
      # `home-manager switch` from niri or a TTY) so it never blocks activation.
      #
      # Hyprland's built-in config auto-reload is disabled via
      # misc:disable_autoreload in settings.conf because reloading with multiple
      # monitors re-evaluates monitor rules and re-attaches workspaces, which
      # shifts focus to a different workspace. Doing the reload here lets us
      # capture the focused workspace beforehand and dispatch back to it after.
      actionScript = ''
        uid="''${UID:-$(id -u)}"
        hypr_root="/run/user/$uid/hypr"

        [ -d "$hypr_root" ] || exit 0

        target_instance=""
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && \
           [ -S "$hypr_root/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
          target_instance="$HYPRLAND_INSTANCE_SIGNATURE"
        else
          newest_mtime=0
          for sock in "$hypr_root"/*/.socket.sock; do
            [ -S "$sock" ] || continue
            instance_dir="''${sock%/.socket.sock}"
            instance="''${instance_dir##*/}"
            mtime=$(stat -c %Y "$sock" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$newest_mtime" ]; then
              newest_mtime="$mtime"
              target_instance="$instance"
            fi
          done
        fi

        [ -n "$target_instance" ] || exit 0

        export HYPRLAND_INSTANCE_SIGNATURE="$target_instance"

        # Capture (workspace, monitor) for every monitor + the globally focused
        # workspace, reload, then restore so multi-monitor reloads don't shift
        # focus.
        before=$(hyprctl monitors -j 2>/dev/null) || exit 0
        focused_ws=$(printf '%s' "$before" \
          | jq -r 'map(select(.focused == true))[0].activeWorkspace.id // empty')
        per_monitor=$(printf '%s' "$before" \
          | jq -r '.[] | "\(.name) \(.activeWorkspace.id)"')

        hyprctl reload >/dev/null 2>&1 || exit 0

        while IFS=' ' read -r mon ws; do
          [ -n "$mon" ] && [ -n "$ws" ] || continue
          hyprctl dispatch focusmonitor "$mon" >/dev/null 2>&1 || true
          hyprctl dispatch workspace "$ws" >/dev/null 2>&1 || true
        done <<<"$per_monitor"

        if [ -n "$focused_ws" ]; then
          hyprctl dispatch workspace "$focused_ws" >/dev/null 2>&1 || true
        fi
      '';
    };
}
