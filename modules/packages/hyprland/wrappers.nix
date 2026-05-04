_: {
  linuxOnlyHomeModules.packagesHyprlandWrappers =
    {
      pkgs,
      homeLib,
      hyprland,
      systemInfo,
      lib,
      config,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      hyprlandPkg = hyprland.packages.${system}.hyprland;
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


      # Create custom Hyprland wrapper with build-time GPU detection
      # This is needed because Nix's mesa-libgbm doesn't include GBM backends
      # The nixGL wrapper is pre-selected in systemInfo based on GPU detection
      hyprland-wrapped = homeLib.gfxName "hyprland" hyprlandPkg;

      # Create a package with both hyprland (lowercase) and Hyprland (uppercase) symlink
      # start-hyprland expects "Hyprland" but we prefer lowercase everywhere else
      hyprland-both-cases = pkgs.linkFarm "hyprland-both-cases" [
        {
          name = "bin/hyprland";
          path = "${hyprland-wrapped}/bin/hyprland";
        }
        {
          name = "bin/Hyprland";
          path = "${hyprland-wrapped}/bin/hyprland";
        }
      ];

      hyprlandPathPrefix = lib.makeBinPath [
        hyprland-wrapped
        hyprland-both-cases
      ];

      # Create start-hyprland wrapper that uses our wrapped hyprland
      # The watchdog monitors the wrapped hyprland process
      # --no-nixgl: disable built-in nixGL detection (we already handle it via hyprland-wrapped)
      # --path: point to our nixGL-wrapped Hyprland binary
      start-hyprland-wrapped = pkgs.runCommand "start-hyprland" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        makeWrapper ${hyprlandPkg}/bin/start-hyprland $out/bin/start-hyprland \
          --add-flags "--no-nixgl --path ${hyprland-wrapped}/bin/hyprland" \
          --prefix PATH : "${pathPrefix}" \
          --prefix PATH : "${hyprlandPathPrefix}" \
          --prefix XDG_DATA_DIRS : "${dataDirsPrefix}"
      '';

      # Create hyprctl wrapper with automatic instance signature detection
      # This fixes the issue where shells started before Hyprland restart have stale
      # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
      hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
        # Use the existing HYPRLAND_INSTANCE_SIGNATURE if its socket is still valid.
        # This is always the case when Hyprland itself dispatches an exec bind.
        # Only auto-detect when the env var is absent or points to a dead instance
        # (e.g. stale shells started before a Hyprland restart).
        uid="''${UID:-$(id -u)}"
        hypr_root="/run/user/$uid/hypr"

        _socket_ok() {
          [ -S "$hypr_root/$1/.socket.sock" ]
        }

        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && _socket_ok "$HYPRLAND_INSTANCE_SIGNATURE"; then
          : # already correct
        else
          # Pick the newest instance (by lock file mtime) that has a live socket.
          current_instance=""
          newest_lock=""
          for lockfile in "$hypr_root"/*/hyprland.lock; do
            [ -e "$lockfile" ] || continue
            instance_name="''${lockfile%/hyprland.lock}"
            instance_name="''${instance_name##*/}"
            if _socket_ok "$instance_name"; then
              if [ -z "$newest_lock" ] || [ "$lockfile" -nt "$newest_lock" ]; then
                newest_lock="$lockfile"
                current_instance="$instance_name"
              fi
            fi
          done
          if [ -n "$current_instance" ]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$current_instance"
          fi
        fi

        # Call hyprctl
        exec ${hyprlandPkg}/bin/hyprctl "$@"
      '';

      # Create custom Xwayland wrapper with nixGL for NVIDIA support
      # This replaces the Xwayland binary completely so KDE will use it
      xwayland-wrapped = homeLib.gfxExe "Xwayland" pkgs.xwayland;
    in
    lib.mkIf config.features.hyprland {
      home.packages = [
        hyprland-both-cases
        hyprctl-wrapped
        start-hyprland-wrapped
        xwayland-wrapped
      ];
    };
}
