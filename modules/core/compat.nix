# TEMPORARY migration shim.
#
# Re-exposes the pre-refactor injected module args (`homeLib`, `constants`,
# `self`, `systemInfo`, assorted flake inputs) on top of the new foundation, so
# aspects can be migrated to `pkgs.stubbe.*` / `config.stubbe.*` one at a time
# while the tree stays evaluable. DELETE this file — and lib.nix + lib/ — once
# no module names any of these args.
{ inputs, self, ... }:
{
  flake.modules.homeManager.compat =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      _module.args = {
        inherit self;
        systemInfo = {
          inherit (pkgs.stubbe) hasNvidia nixGLBin;
          nixGLWrapper = pkgs.stubbe.nixGL;
        };
        homeLib = import (self + "/lib.nix") {
          inherit lib pkgs self;
          inherit (config.stubbe) gfx;
        };
        constants = {
          paths = {
            inherit (config.stubbe.paths) dotfiles nixBin wallpaper;
            term = config.stubbe.paths.terminal;
          };
          theme = pkgs.stubbe.theme;
        };
        inherit (inputs)
          fenix
          srv
          treeman
          zsh-vim-mode
          zsh-fzf-artisan
          zsh-fzf-npm-run
          ;
        "hyprland-guiutils" = inputs."hyprland-guiutils";
      };
    };
}
