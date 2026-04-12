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

      niri-wrapped = homeLib.gfxBinIncDrivers "niri" pkgs.niri;

      start-niri = pkgs.runCommand "start-niri" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        makeWrapper ${pkgs.writeShellScript "start-niri-inner" ''
          export XDG_CURRENT_DESKTOP=niri
          export XDG_SESSION_TYPE=wayland
          export XDG_SESSION_DESKTOP=niri

          ${lib.optionalString systemInfo.hasNvidia ''
          export __GLX_VENDOR_LIBRARY_NAME=nvidia
          export LIBVA_DRIVER_NAME=nvidia
          export MOZ_DISABLE_RDD_SANDBOX=1
          export NVD_BACKEND=direct
          ''}

          exec ${niri-wrapped}/bin/niri
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
