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
      # session). Mirrors the hyprctl-wrapped pattern. niri's socket lives
      # at /run/user/$UID/niri.<wayland-display>.<pid>.sock.
      niri-wrapped = pkgs.writeShellScriptBin "niri" ''
        uid="''${UID:-$(id -u)}"
        sock_dir="/run/user/$uid"

        _socket_ok() {
          [ -S "$1" ]
        }

        if [ -n "$NIRI_SOCKET" ] && _socket_ok "$NIRI_SOCKET"; then
          : # current value still valid
        else
          # Pick the newest live niri socket. Filename ends with the
          # compositor PID, so we can verify the process is still alive.
          newest_socket=""
          newest_mtime=0
          for sock in "$sock_dir"/niri.*.sock; do
            _socket_ok "$sock" || continue
            base="''${sock##*/}"
            pid="''${base%.sock}"
            pid="''${pid##*.}"
            [ -d "/proc/$pid" ] || continue
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
