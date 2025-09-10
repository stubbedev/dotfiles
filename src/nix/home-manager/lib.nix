{ lib, ... }:

{
  # Load all .nix files from a directory and return their contents as a list
  loadPackagesFromDir = dir: args:
    let
      nixFiles = lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir dir);

      loadFile = name: import (dir + "/${name}") args;
    in builtins.concatLists (map loadFile (builtins.attrNames nixFiles));

  # Load modules from a directory for imports
  loadModulesFromDir = dir:
    let
      nixFiles = lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir dir);
    in map (name: dir + "/${name}") (builtins.attrNames nixFiles);

  # Conditionally load packages based on environment variable
  conditionalPackages = condition: packages:
    if condition then packages else [ ];
}

