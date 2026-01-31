_: {
  flake.modules.homeManager.packagesHyprlandWrappers =
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
      inherit (pkgs) lib;
      inherit (pkgs.stdenv.hostPlatform) system;
      hyprlandPkg = hyprland.packages.${system}.hyprland;

      gbmPaths = lib.unique [
        "/usr/lib64/gbm"
        "/usr/lib/gbm"
        "/run/opengl-driver/lib/gbm"
        "/run/opengl-driver-32/lib/gbm"
      ];

      driPaths = lib.unique [
        "/usr/lib64/dri"
        "/usr/lib/dri"
        "/run/opengl-driver/lib/dri"
        "/run/opengl-driver-32/lib/dri"
      ];

      # Create custom Hyprland wrapper with build-time GPU detection
      # This is needed because Nix's mesa-libgbm doesn't include GBM backends
      # The nixGL wrapper is pre-selected in systemInfo based on GPU detection
      hyprland-wrapped = homeLib.gfxNameWith "hyprland" ''
        # Set GBM/DRI paths to use system libraries (needed on non-NixOS)
        export GBM_BACKENDS_PATH=${lib.concatStringsSep ":" gbmPaths}
        export LIBGL_DRIVERS_PATH=${lib.concatStringsSep ":" driPaths}
      '' hyprlandPkg;

      # Create a package with both hyprland (lowercase) and Hyprland (uppercase) symlink
      # start-hyprland expects "Hyprland" but we prefer lowercase everywhere else
      hyprland-both-cases = pkgs.runCommand "hyprland-both-cases" { } ''
        mkdir -p $out/bin
        ln -s ${hyprland-wrapped}/bin/hyprland $out/bin/hyprland
        ln -s ${hyprland-wrapped}/bin/hyprland $out/bin/Hyprland
      '';

      # Create start-hyprland wrapper that uses our wrapped hyprland
      # The watchdog monitors the wrapped hyprland process
      start-hyprland-wrapped = pkgs.writeShellScriptBin "start-hyprland" ''
        # Ensure session PATH includes user and flatpak bins
        desired_paths=(
          "$HOME/.cargo/bin"
          "$HOME/.nix-profile/bin"
          "$HOME/.local/bin"
          "$HOME/.local/share/flatpak/exports/bin"
          "/var/lib/flatpak/exports/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
        )
        prefix_paths=""
        for desired_path in "''${desired_paths[@]}"; do
          case ":$PATH:" in
            *":''${desired_path}:"*) ;;
            *)
              if [ -z "$prefix_paths" ]; then
                prefix_paths="$desired_path"
              else
                prefix_paths="$prefix_paths:$desired_path"
              fi
              ;;
          esac
        done
        if [ -n "$prefix_paths" ]; then
          export PATH="$prefix_paths:$PATH"
        fi

        # Ensure XDG_DATA_DIRS includes Flatpak/Nix desktop entries
        desired_data_dirs=(
          "$HOME/.local/share/flatpak/exports/share"
          "$HOME/.nix-profile/share"
          "/nix/var/nix/profiles/default/share"
          "/var/lib/flatpak/exports/share"
          "/usr/local/share"
          "/usr/share"
        )
        prefix_data_dirs=""
        for desired_dir in "''${desired_data_dirs[@]}"; do
          case ":$XDG_DATA_DIRS:" in
            *":''${desired_dir}:"*) ;;
            *)
              if [ -z "$prefix_data_dirs" ]; then
                prefix_data_dirs="$desired_dir"
              else
                prefix_data_dirs="$prefix_data_dirs:$desired_dir"
              fi
              ;;
          esac
        done
        if [ -n "$prefix_data_dirs" ]; then
          if [ -n "$XDG_DATA_DIRS" ]; then
            export XDG_DATA_DIRS="$prefix_data_dirs:$XDG_DATA_DIRS"
          else
            export XDG_DATA_DIRS="$prefix_data_dirs"
          fi
        fi

        # Add our wrapped Hyprland to PATH so start-hyprland can find it
        export PATH="${hyprland-wrapped}/bin:$PATH"

        # Ensure we have the Hyprland binary available (both cases)
        # start-hyprland looks for "Hyprland" with capital H
        export PATH="${hyprland-both-cases}/bin:$PATH"

        # Use the official start-hyprland watchdog
        exec ${hyprlandPkg}/bin/start-hyprland "$@"
      '';

      # Create hyprctl wrapper with automatic instance signature detection
      # This fixes the issue where shells started before Hyprland restart have stale
      # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
      hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
        # Auto-detect the current active Hyprland instance
        # Prefer instances with a listening control socket
        CURRENT_INSTANCE=""

        for lockfile in $(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null); do
          instance_dir=$(dirname "$lockfile")
          instance_name=$(basename "$instance_dir")
          socket_path="$instance_dir/.socket.sock"

          if [ -S "$socket_path" ] && ss -xl | grep -q "$socket_path"; then
            CURRENT_INSTANCE="$instance_name"
            break
          fi
        done

        # Fallback to newest lock file if no listening socket found
        if [ -z "$CURRENT_INSTANCE" ]; then
          CURRENT_INSTANCE=$(ls -t /run/user/$(id -u)/hypr/*/hyprland.lock 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs basename 2>/dev/null)
        fi

        if [ -n "$CURRENT_INSTANCE" ]; then
          export HYPRLAND_INSTANCE_SIGNATURE="$CURRENT_INSTANCE"
        fi
        # If no active instance found, fall back to existing env var (if any)

        # Call hyprctl
        exec ${hyprlandPkg}/bin/hyprctl "$@"
      '';

      # Create custom Xwayland wrapper with nixGL for NVIDIA support
      # This replaces the Xwayland binary completely so KDE will use it
      xwayland-wrapped = pkgs.writeShellScriptBin "Xwayland" (
        if systemInfo.hasNvidia then
          ''
            # NVIDIA: Run Xwayland through nixGLNvidia for proper GPU acceleration
            export GBM_BACKENDS_PATH="${lib.concatStringsSep ":" gbmPaths}"
            export LIBGL_DRIVERS_PATH="${lib.concatStringsSep ":" driPaths}"

            # Find the versioned nixGLNvidia binary
            NIXGL_BIN=$(ls ${systemInfo.nixGLWrapper}/bin/nixGLNvidia* 2>/dev/null | head -1)
            if [ -z "$NIXGL_BIN" ]; then
              echo "Error: nixGLNvidia not found" >&2
              exit 1
            fi

            exec "$NIXGL_BIN" ${pkgs.xwayland}/bin/Xwayland "$@"
          ''
        else
          ''
            # Intel/AMD: Run Xwayland through nixGLIntel
            export GBM_BACKENDS_PATH="${lib.concatStringsSep ":" gbmPaths}"
            export LIBGL_DRIVERS_PATH="${lib.concatStringsSep ":" driPaths}"

            exec ${systemInfo.nixGLWrapper}/bin/nixGLIntel ${pkgs.xwayland}/bin/Xwayland "$@"
          ''
      );
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
