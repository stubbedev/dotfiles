# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# The "find the live Hyprland compositor instance" shell function, shared by
# the hyprctl wrapper, wayle-launch and the post-switch reload step. Emitted
# as text because the three scripts are separate derivations.
#
#   hypr_instance <first|newest> <attempts> <sleep>
#
# Prints the instance signature (possibly empty). Trusts
# $HYPRLAND_INSTANCE_SIGNATURE when its socket is live; otherwise scans the
# running instances, picking the first match or the newest socket. `attempts`
# > 1 polls for a compositor that is still starting up.
_: {
  stubbe.pkgsLib.hypr = _: {
    instanceFn = ''
    hypr_instance() {
      _hi_pick=$1
      _hi_attempts=$2
      _hi_sleep=$3
      _hi_root="/run/user/$(id -u)/hypr"
      _hi_found=""
      _hi_newest=0

      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
        && [ -S "$_hi_root/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]
      then
        _hi_found=$HYPRLAND_INSTANCE_SIGNATURE
      else
        _hi_attempt=0
        while [ "$_hi_attempt" -lt "$_hi_attempts" ]; do
          for sock in "$_hi_root"/*/.socket.sock; do
            [ -S "$sock" ] || continue
            _hi_instance=''${sock%/.socket.sock}
            _hi_instance=''${_hi_instance##*/}
            if [ "$_hi_pick" = first ]; then
              _hi_found=$_hi_instance
              break
            fi
            _hi_mtime=$(stat -c %Y "$sock" 2>/dev/null || echo 0)
            if [ "$_hi_mtime" -gt "$_hi_newest" ]; then
              _hi_newest=$_hi_mtime
              _hi_found=$_hi_instance
            fi
          done
          if [ -n "$_hi_found" ]; then break; fi
          if [ -n "$_hi_sleep" ]; then sleep "$_hi_sleep"; fi
          _hi_attempt=$(( _hi_attempt + 1 ))
        done
      fi

      printf '%s' "$_hi_found"
    }
  '';
  };
}
