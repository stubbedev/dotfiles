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

  import = importedPrograms;

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
    ".config/nvim".source = ./../../nvim;
    # ".config/lazygit/config.yml".source = dotsDir + "/lazygit/config.yml";
    # ".config/lazygit/state.yml".text = "startuppopupversion: 5";
    # ".config/alacritty/alacritty.toml".source = dotsDir + "/alacritty/alacritty.toml";
    # ".config/alacritty/catppuccin-mocha.toml".source = dotsDir + "/alacritty/alacritty.toml";
    # ".config/rofi/catppuccin-mocha.rasi".source = dotsDir + "/rofi/catppuccin-mocha.rasi";
    # ".config/rofi/catppuccin-default.rasi".source = dotsDir + "/rofi/catppuccin-default.rasi";
    # ".config/rofi/config.rasi".source = dotsDir + "/rofi/config.rasi";
    # ".config/btop/btop.conf".source = dotsDir + "/btop/btop.conf";
    # ".config/btop/themes/catppuccin_frappe.theme".source = dotsDir + "/btop/themes/catppuccin_frappe.theme";
    # ".config/btop/themes/catppuccin_latte.theme".source = dotsDir + "/btop/themes/catppuccin_latte.theme";
    # ".config/btop/themes/catppuccin_macchiato.theme".source = dotsDir + "/btop/themes/catppuccin_macchiato.theme";
    # ".config/btop/themes/catppuccin_mocha.theme".source = dotsDir + "/btop/themes/catppuccin_mocha.theme";
    # ".config/swaync/style.css".source = dotsDir + "/swaync/style.css";
    # ".config/waybar/config.jsonc".source = dotsDir + "/waybar/config.jsonc";
    # ".config/waybar/style.css".source = dotsDir + "/waybar/style.css";
    # ".config/hypr/hyprland.conf".source = dotsDir + "/hypr/hyprland.conf";
    # ".config/hypr/hyprlock.conf".source = dotsDir + "/hypr/hyprlock.conf";
    # ".config/hypr/hypridle.conf".source = dotsDir + "/hypr/hypridle.conf";
    # ".config/hypr/hyprpaper.conf".source = dotsDir + "/hypr/hyprpaper.conf";
    # ".config/hypr/hyprsunset.conf".source = dotsDir + "/hypr/hyprsunset.conf";
    # ".config/hypr/keybinds.conf".source = dotsDir + "/hypr/keybinds.conf";
    # ".config/hypr/monitors.conf".source = dotsDir + "/hypr/monitors.conf";
    # ".config/hypr/settings.conf".source = dotsDir + "/hypr/settings.conf";
    # ".config/hypr/theme.conf".source = dotsDir + "/hypr/theme.conf";
    # ".config/hypr/env.conf".source = dotsDir + "/hypr/env.conf";
    # ".config/hypr/scripts".source = dotsDir + "/hypr/scripts";
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
  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  programs.neovim.enable = true; # FIXME: Add lazyvim config
  programs.kitty.enable = true;

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

}
