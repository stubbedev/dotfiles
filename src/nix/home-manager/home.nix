{ config, lib, pkgs, self, ... }:

let
  pkgsDir = self + "/pkgs";
  nixFiles = builtins.filter (name: builtins.match ".*\\.nix$" name != null)
    (builtins.attrNames (builtins.readDir pkgsDir));
  packageLists =
    map (file: import (pkgsDir + "/${file}") { inherit pkgs; }) nixFiles;

  programsDir = self + "/programs";
  nixPrograms = builtins.filter (name: builtins.match ".*\\.nix$" name != null)
    (builtins.attrNames (builtins.readDir programsDir));
  importedPrograms =
    map (name: import (programsDir + "/${name}")) nixPrograms;
in {

  imports = importedPrograms;

  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";
  home.stateVersion = "25.05";

  # FIXME: need to migrate the hyprland config files to avoid conflicts
  # wayland.windowManager.hyprland.enable = true;

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (pkg: true);
    allowInsecure = true;
    allowInsecurePredicate = (pkg: true);
  };

  home.packages = builtins.concatLists packageLists;

  home.file = {
    ".zshrc".text = "source /home/stubbe/.stubbe/src/zsh/init";
    ".ideavimrc".source = ./../../ideavim/ideavimrc;
    ".tmux.conf".source = ./../../tmux/tmux.conf;
    ".config/nvim".source = ./../../nvim;
    ".config/lazygit/config.yml".source = ./../../lazygit/config.yml;
    ".config/lazygit/state.yml".text = "startuppopupversion: 5";
    ".config/alacritty".source = ./../../alacritty;
    ".config/rofi".source = ./../../rofi;
    ".config/btop".source = ./../../btop;
    ".config/swaync".source = ./../../swaync;
    ".config/waybar".source = ./../../waybar;
    ".config/hypr".source = ./../../hypr;
    ".config/xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=gtk;wlr
    '';
  };
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = "1";
    NIXPKGS_ALLOW_INSECURE = "1";
    NIXOS_OZONE_WL = "1";
    EDITOR = "nvim";
    DISPLAY = ":1";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    GOROOT = "/home/stubbe/.go";
    GOPATH = "/home/stubbe/go";
    DEPLOYER_REMOTE_USER = "abs";
  };

  home.activation.installTpm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone --quiet https://github.com/tmux-plugins/tpm "$HOME"/.tmux/plugins/tpm
    fi
  '';

  systemd.user.services = {
    waybar-reload-on-power-profile = {
      Unit = {
        Description = "Reload Waybar when power-profiles-daemon starts";
        After = [ "graphical-session.target" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "simple";
        ExecStart = "%h/.stubbe/src/hypr/scripts/wait_for_power_profiles.sh";
        Restart = "no";
      };
    };
  };

  programs.home-manager.enable = true;
}
