_: {
  enableIf = { config, ... }: config.features.niri;
  args =
    { ... }:
    {
      # Reload niri after every successful home-manager switch when a live
      # niri session is detected. Skipped silently otherwise (e.g. running
      # `home-manager switch` from Hyprland or a TTY) so it never blocks
      # activation.
      actionScript = ''
        uid="''${UID:-$(id -u)}"
        sock_dir="/run/user/$uid"
        stable_sock="$sock_dir/niri-current.sock"

        # Prefer the spawn-at-startup symlink (niri-current.sock); fall
        # back to scanning for the newest live PID-named socket if it
        # hasn't landed yet.
        target_socket=""
        if [ -S "$stable_sock" ]; then
          target_socket="$stable_sock"
        else
          newest_mtime=0
          for sock in "$sock_dir"/niri.*.sock; do
            [ -S "$sock" ] || continue
            base="''${sock##*/}"
            pid="''${base%.sock}"
            pid="''${pid##*.}"
            [ -d "/proc/$pid" ] || continue
            mtime=$(stat -c %Y "$sock" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$newest_mtime" ]; then
              newest_mtime="$mtime"
              target_socket="$sock"
            fi
          done
        fi

        if [ -n "$target_socket" ]; then
          NIRI_SOCKET="$target_socket" niri msg action load-config-file >/dev/null 2>&1 || true
        fi
      '';
    };
}
