_: {
  flake.modules.homeManager.packagesNiriWrappers =
    {
      pkgs,
      homeLib,
      systemInfo,
      lib,
      config,
      ...
    }:
    let
      inherit (pkgs) lib;
      homeDir = config.home.homeDirectory;
      desiredPaths =
        map (path: lib.replaceStrings [ "$HOME" ] [ homeDir ] path) config.home.sessionPath;

      desiredDataDirs =
        let
          rawDataDirs = lib.splitString ":" (config.home.sessionVariables.XDG_DATA_DIRS or "");
          replaceHome = path: lib.replaceStrings [ "$HOME" ] [ homeDir ] path;
          isPlaceholder = value: value == "$XDG_DATA_DIRS" || value == "\${XDG_DATA_DIRS}";
        in
        map replaceHome (builtins.filter (value: value != "" && !isPlaceholder value) rawDataDirs);

      pathPrefix = lib.concatStringsSep ":" desiredPaths;
      dataDirsPrefix = lib.concatStringsSep ":" desiredDataDirs;

      # Same nixGL wrapping as Hyprland — host Mesa drivers can be older
      # than Nix's libgbm (e.g. Ubuntu 25.2 vs Nix 26.x), so we need
      # nixGL's bundled drivers for ABI match.
      niri-gfx-wrapped = homeLib.gfxName "niri" pkgs.niri;

      # Auto-detect NIRI_SOCKET so `niri msg ...` works in shells started
      # before niri (e.g. tmux sessions, terminals from a previous DM
      # session). Mirrors the hyprctl-wrapped pattern. niri's real socket
      # name embeds its PID (niri.<wayland-display>.<pid>.sock); a niri
      # spawn-at-startup hook keeps a stable niri-current.sock symlink to
      # the live socket so we don't have to scan and pick the newest.
      niri-wrapped = pkgs.writeShellScriptBin "niri" ''
        uid="''${UID:-$(id -u)}"
        sock_dir="/run/user/$uid"
        stable_sock="$sock_dir/niri-current.sock"

        # Validate a niri socket path: it has to be a socket, and the PID
        # encoded in the filename has to still be a running process. We
        # readlink first so the niri-current.sock symlink resolves to its
        # PID-named target.
        _niri_alive() {
          local target base pid
          target=$(readlink -f "$1" 2>/dev/null) || target="$1"
          [ -S "$target" ] || return 1
          base="''${target##*/}"
          pid="''${base%.sock}"
          pid="''${pid##*.}"
          case "$pid" in [0-9]*) [ -d "/proc/$pid" ] ;; *) return 1 ;; esac
        }

        if [ -n "$NIRI_SOCKET" ] && _niri_alive "$NIRI_SOCKET"; then
          : # current value still valid
        elif _niri_alive "$stable_sock"; then
          export NIRI_SOCKET="$stable_sock"
        else
          # Fallback: niri is up but the spawn-at-startup symlink hasn't
          # landed yet (or got removed). Pick the newest live niri socket.
          newest_socket=""
          newest_mtime=0
          for sock in "$sock_dir"/niri.*.sock; do
            _niri_alive "$sock" || continue
            mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$sock" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$newest_mtime" ]; then
              newest_mtime="$mtime"
              newest_socket="$sock"
            fi
          done
          if [ -n "$newest_socket" ]; then
            export NIRI_SOCKET="$newest_socket"
          fi
        fi

        # Guard against accidentally starting a nested compositor inside a
        # live niri session. A bare `niri` (or `niri --session`, `niri -c
        # somecfg`, …) launches a new compositor, libwayland falls back
        # to wayland-N, and the leftover stale socket breaks waybar and
        # friends on next start. niri itself has no built-in for this.
        #
        # niri's CLI is `niri [OPTIONS] [-- COMMAND...]` or `niri
        # SUBCOMMAND`. So instead of enumerating subcommands (which drift
        # between niri versions), we walk the args: the first non-option
        # positional encountered before `--` is a subcommand and means no
        # compositor starts. Help / version flags exit early; -c/--config
        # consumes its value. Bare args, only options, or `--` mean
        # compositor.
        # NIRI_ALLOW_NESTED=1 bypasses the guard.
        _starts_compositor() {
          local arg expecting_value=0
          for arg in "$@"; do
            if [ "$expecting_value" -eq 1 ]; then
              expecting_value=0
              continue
            fi
            case "$arg" in
              -h|--help|-V|--version) return 1 ;;
              -c|--config) expecting_value=1 ;;
              --) return 0 ;;
              -*) ;;
              *) return 1 ;;
            esac
          done
          return 0
        }

        if [ -n "$NIRI_SOCKET" ] && [ -z "''${NIRI_ALLOW_NESTED:-}" ] \
           && _starts_compositor "$@"; then
          echo "niri: a live niri session is already running ($NIRI_SOCKET)" >&2
          echo "      refusing to start a nested compositor; use 'niri msg …' for IPC" >&2
          echo "      (set NIRI_ALLOW_NESTED=1 to override)" >&2
          exit 1
        fi

        exec ${niri-gfx-wrapped}/bin/niri "$@"
      '';

      start-niri = pkgs.runCommand "start-niri" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        makeWrapper ${pkgs.writeShellScript "start-niri-inner" ''
          export XDG_CURRENT_DESKTOP=niri
          export XDG_SESSION_TYPE=wayland
          export XDG_SESSION_DESKTOP=niri

          # Force DRM/KMS mode: unset any inherited Wayland/X11 display from the
          # parent session (e.g. GDM's own Wayland compositor sets WAYLAND_DISPLAY).
          # Without this, niri would start nested under GDM instead of taking DRM.
          unset WAYLAND_DISPLAY
          unset DISPLAY

          ${lib.optionalString systemInfo.hasNvidia ''
          export __GLX_VENDOR_LIBRARY_NAME=nvidia
          export LIBVA_DRIVER_NAME=nvidia
          export MOZ_DISABLE_RDD_SANDBOX=1
          export NVD_BACKEND=direct
          ''}

          if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
            exec ${pkgs.dbus}/bin/dbus-run-session -- ${niri-gfx-wrapped}/bin/niri --session
          else
            exec ${niri-gfx-wrapped}/bin/niri --session
          fi
        ''} $out/bin/start-niri \
          --prefix PATH : "${pathPrefix}" \
          --prefix XDG_DATA_DIRS : "${dataDirsPrefix}"
      '';
    in
    lib.mkIf config.features.niri {
      home.packages = [
        niri-wrapped
        start-niri
      ];
    };
}
