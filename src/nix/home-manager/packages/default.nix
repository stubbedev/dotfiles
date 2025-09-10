# Enhanced package loader with better organization
# Loads packages in optimal order with improved categorization
args:
let
  lib = args.lib or (import <nixpkgs/lib>);

  # Filter function to exclude metadata and default files
  packageFilter = name:
    name != "default.nix" && name != "metadata.nix" && name != "README.md"
    && lib.hasSuffix ".nix" name;

  # Load packages using direct file filtering
  nixFiles =
    lib.filterAttrs (name: type: type == "regular" && packageFilter name)
    (builtins.readDir ./.);

  loadFile = name: import (./. + "/${name}") args;
  packageLists = map loadFile (lib.attrNames nixFiles);
in builtins.concatLists packageLists

