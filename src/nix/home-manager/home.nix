{ config, lib, pkgs, self, ... }:

let
  pkgsDir = self + "/pkgs";
  dotsDir = self + "/src";
  nixFiles = builtins.filter (name: builtins.match ".*\\.nix$" name != null)
    (builtins.attrNames (builtins.readDir pkgsDir));
  packageLists =
    map (file: import (pkgsDir + "/${file}") { inherit pkgs; }) nixFiles;
in {
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

  home.file = {
    ".zshrc".text = "source /home/stubbe/.stubbe/src/zsh/init";
    ".tmux.conf".source = dotsDir + "/tmux/tmux.conf";
    ".ideavim".source = dotsDir + "/ideavim/ideavimrc";
    ".config/nvim".source = dotsDir + "/nvim";
    ".config/lazygit/config.yml".source = dotsDir + "/lazygit/config.yml";
    ".config/lazygit/state.yml".text = "startuppopupversion: 5";
    ".config/alacritty".source = dotsDir + "/alacritty";
    ".config/hypr".source = dotsDir + "/hypr";
    ".config/systemd/user/waybar-reload-on-power-profile.service".source = dotsDir + "/hypr/services/waybar-reload-on-power-profile.service";
    ".config/rofi".source = dotsDir + "/rofi";
    ".config/btop".source = dotsDir + "/btop";
    ".config/sway".source = dotsDir + "/sway";
    ".config/swaync".source = dotsDir + "/swaync";
    ".config/waybar".source = dotsDir + "/waybar";
    ".config/xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=gtk;wlr
    '';
  };
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = 1;
    NIXPKGS_ALLOW_INSECURE = 1;
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
  programs.home-manager.enable = true;
  programs.neovim.enable = true;
  programs.git = {
    enable = true;
    userName = "Alexander Bugge Stage";
    userEmail = "abs@stubbe.dev";
    extraConfig = {
      core = {
        excludesfile = "~/.gitignore";
        editor = "nvim";
      };
      push.autoSetupRemote = true;
      advice.setUpstreamFailure = false;
    };
  };

  systemd.user.services = {
    waybar-reload-on-power-profile = {
      enable = true;
      wantedBy = [ "default.target" ];
    };
  };
}

