# Optimized Hyprland package loader
args:
let
  lib = args.lib or (import <nixpkgs/lib>);
  homeLib = import ../lib.nix { inherit lib; };
in homeLib.loadPackagesFromDir ./. args

