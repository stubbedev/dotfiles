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
      homeDir = config.home.homeDirectory;
      desiredPaths = [
        "${homeDir}/.cargo/bin"
        "${homeDir}/.nix-profile/bin"
        "${homeDir}/.local/bin"
        "${homeDir}/.local/share/flatpak/exports/bin"
        "/var/lib/flatpak/exports/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ];

      desiredDataDirs = [
        "${homeDir}/.local/share/flatpak/exports/share"
        "${homeDir}/.nix-profile/share"
        "/nix/var/nix/profiles/default/share"
        "/var/lib/flatpak/exports/share"
        "/usr/local/share"
        "/usr/share"
      ];

      pathPrefix = lib.concatStringsSep ":" desiredPaths;
      dataDirsPrefix = lib.concatStringsSep ":" desiredDataDirs;


      # Create custom Hyprland wrapper with build-time GPU detection
      # This is needed because Nix's mesa-libgbm doesn't include GBM backends
      # The nixGL wrapper is pre-selected in systemInfo based on GPU detection
      hyprland-wrapped = homeLib.gfxBinIncDrivers "hyprland" hyprlandPkg;

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
      start-hyprland-wrapped = pkgs.runCommand "start-hyprland" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        makeWrapper ${hyprlandPkg}/bin/start-hyprland $out/bin/start-hyprland \
          --prefix PATH : "${pathPrefix}" \
          --prefix PATH : "${hyprlandPathPrefix}" \
          --prefix XDG_DATA_DIRS : "${dataDirsPrefix}"
      '';

      # Create hyprctl wrapper with automatic instance signature detection
      # This fixes the issue where shells started before Hyprland restart have stale
      # HYPRLAND_INSTANCE_SIGNATURE values (e.g., in tmux sessions or long-running terminals)
      hyprctl-wrapped = pkgs.writeShellScriptBin "hyprctl" ''
        # Auto-detect the current active Hyprland instance
        # Prefer instances with a listening control socket
        uid="''${UID:-$(id -u)}"
        hypr_root="/run/user/$uid/hypr"
        current_instance=""
        newest_lock=""

        for lockfile in "$hypr_root"/*/hyprland.lock; do
          [ -e "$lockfile" ] || continue
          instance_dir="''${lockfile%/hyprland.lock}"
          instance_name="''${instance_dir##*/}"
          socket_path="$instance_dir/.socket.sock"

          if [ -S "$socket_path" ]; then
            case "$(ss -xl)" in
              *"$socket_path"*)
                current_instance="$instance_name"
                break
                ;;
            esac
          fi

          if [ -z "$newest_lock" ] || [ "$lockfile" -nt "$newest_lock" ]; then
            newest_lock="$lockfile"
          fi
        done

        # Fallback to newest lock file if no listening socket found
        if [ -z "$current_instance" ] && [ -n "$newest_lock" ]; then
          instance_dir="''${newest_lock%/hyprland.lock}"
          current_instance="''${instance_dir##*/}"
        fi

        if [ -n "$current_instance" ]; then
          export HYPRLAND_INSTANCE_SIGNATURE="$current_instance"
        fi
        # If no active instance found, fall back to existing env var (if any)

        # Call hyprctl
        exec ${hyprlandPkg}/bin/hyprctl "$@"
      '';

      # Create custom Xwayland wrapper with nixGL for NVIDIA support
      # This replaces the Xwayland binary completely so KDE will use it
      xwayland-wrapped = homeLib.gfxBinExeIncDrivers "Xwayland" pkgs.xwayland;
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
