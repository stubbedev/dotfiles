# Compositor session-path resolution.
{ lib }:
{
  # Resolve config.home.sessionPath / sessionVariables.XDG_DATA_DIRS into
  # ":"-joined absolute strings, suitable for makeWrapper --prefix. $HOME
  # placeholders get expanded against config.home.homeDirectory; the
  # literal $XDG_DATA_DIRS placeholder (which the home-manager schema
  # injects) is dropped.
  resolveSessionPaths =
    config:
    let
      homeDir = config.home.homeDirectory;
      replaceHome = path: lib.replaceStrings [ "$HOME" ] [ homeDir ] path;
      isPlaceholder = v: v == "$XDG_DATA_DIRS" || v == "\${XDG_DATA_DIRS}";

      paths = map replaceHome config.home.sessionPath;
      rawDataDirs = lib.splitString ":" (config.home.sessionVariables.XDG_DATA_DIRS or "");
      dataDirs = map replaceHome (builtins.filter (v: v != "" && !isPlaceholder v) rawDataDirs);
    in
    {
      pathPrefix = lib.concatStringsSep ":" paths;
      dataDirsPrefix = lib.concatStringsSep ":" dataDirs;
    };
}
