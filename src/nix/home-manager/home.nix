{ config, lib, pkgs, ... }:

let
  pkgsDir = ./pkgs;
  nixFiles = builtins.filter (name: builtins.match ".*\\.nix$" name != null)
    (builtins.attrNames (builtins.readDir pkgsDir));
  packageLists =
    map (file: import (pkgsDir + "/${file}") { inherit pkgs; }) nixFiles;

  programsDir = ./programs;
  nixPrograms = builtins.filter (name: builtins.match ".*\\.nix$" name != null)
    (builtins.attrNames (builtins.readDir programsDir));
  importedPrograms =
    map (name: import (programsDir + "/${name}")) nixPrograms;
in {

  imports = importedPrograms;

  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";
  home.stateVersion = "25.05";

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (pkg: true);
    allowInsecure = true;
    allowInsecurePredicate = (pkg: true);
  };

  home.packages = builtins.concatLists packageLists;

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.variables = [ "--all" ];
    extraConfig = builtins.readFile ./../../hypr/hyprland.conf;
  };

  home.file = {
    ".zshrc".text = "source /home/stubbe/.stubbe/src/zsh/init";
    ".ideavimrc".source = ./../../ideavim/ideavimrc;
    ".tmux.conf".source = ./../../tmux/tmux.conf;
    ".config/lazygit/config.yml".source = ./../../lazygit/config.yml;
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

  home.activation.stubbePostBuild = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone --quiet https://github.com/tmux-plugins/tpm "$HOME"/.tmux/plugins/tpm
    fi
    rm -rf "$HOME/.config/nvim" && ln -sf "$HOME/.stubbe/src/nvim" "$HOME/.config/nvim"
    mkdir -p "$HOME/.config/lazygit" && echo "startuppopupversion: 5" > "$HOME/.config/lazygit/state.yml"
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
