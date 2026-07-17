_: {
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, ... }:
    let
      # HM activation runs with a stripped PATH that excludes the user profile,
      # so `hyprctl` (installed via modules/packages/hyprland/wrappers.nix) is
      # not directly callable. Reach into the profile by absolute path instead.
      hyprctl = "${config.home.profileDirectory}/bin/hyprctl";
    in
    {
      # Reload Hyprland after every successful home-manager switch when a live
      # Hyprland session is detected. Skipped silently otherwise (e.g. running
      # `home-manager switch` from a TTY) so it never blocks activation.
      #
      # Hyprland's built-in config auto-reload is disabled via
      # misc.disable_autoreload in hyprland.lua because reloading with multiple
      # monitors re-evaluates monitor rules and re-attaches workspaces, which
      # shifts focus to a different workspace. Doing the reload here lets us
      # capture the focused workspace beforehand and dispatch back to it after.
      #
      # Wrapped in a subshell + `|| true` so any `exit` or set -e failure inside
      # only aborts this hook, not the entire HM activation script.
      actionScript = ''
        (
          uid="''${UID:-$(id -u)}"
          hypr_root="/run/user/$uid/hypr"

          [ -d "$hypr_root" ] || exit 0

          target_instance=""
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && \
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
          before=$(${hyprctl} monitors -j 2>/dev/null) || exit 0
          focused_ws=$(printf '%s' "$before" \
            | jq -r 'map(select(.focused == true))[0].activeWorkspace.id // empty')
          per_monitor=$(printf '%s' "$before" \
            | jq -r '.[] | "\(.name) \(.activeWorkspace.id)"')

          ${hyprctl} reload >/dev/null 2>&1 || exit 0

          # Reload re-enables eDP-1 from monitors.conf and auto-positions the
          # externals to its right; re-apply the lid-closed layout before
          # workspace restore so workspaces don't migrate back. reflow_monitors
          # disables eDP and re-packs the externals from 0,0 in one pass, so the
          # external is not left stranded at a half-screen offset. (`hyprctl
          # keyword` is rejected under the Lua config — "keyword can't work with
          # non-legacy parsers. Use eval." — so drive it through the exposed Lua
          # reflow_monitors instead.)
          if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
            ${hyprctl} eval "reflow_monitors(true)" >/dev/null 2>&1 || true
          fi

          # Legacy `hyprctl dispatch <name> <args>` is rejected under the Lua
          # config (it is parsed as hl.dispatch(<args>) Lua); pass a Lua
          # dispatcher expression instead. focusmonitor/workspace both map to
          # hl.dsp.focus{ monitor = ... } / hl.dsp.focus{ workspace = ... }.
          while IFS=' ' read -r mon ws; do
            [ -n "$mon" ] && [ -n "$ws" ] || continue
            ${hyprctl} dispatch "hl.dsp.focus({ monitor = '$mon' })" >/dev/null 2>&1 || true
            ${hyprctl} dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1 || true
          done <<<"$per_monitor"

          if [ -n "$focused_ws" ]; then
            ${hyprctl} dispatch "hl.dsp.focus({ workspace = $focused_ws })" >/dev/null 2>&1 || true
          fi
        ) || true
      '';
    };
}
