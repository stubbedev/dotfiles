{ config, lib, pkgs, nixGL, ... }:
let
  nixglWrapper = builtins.getEnv "NIXGL_WRAPPER";
  homePackages = builtins.concatLists
    (map (file: import (./packages + "/${file}") { inherit pkgs config; })
      (builtins.filter (f: builtins.match ".*\\.nix$" f != null)
        (builtins.attrNames (builtins.readDir ./packages))));
in {
  nixGL = {
    packages = nixGL.packages;
    defaultWrapper = nixglWrapper;
  };

  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";
  home.stateVersion = "25.05";

  home.packages = homePackages;

  imports = [ ./programs/git.nix ];

  home.file = {
    ".zshrc".text = "source ${config.home.homeDirectory}/.stubbe/src/zsh/init";
    ".ideavimrc".source = ./../../ideavim/ideavimrc;
    ".tmux.conf".source = ./../../tmux/tmux.conf;
    ".config/lazygit/config.yml".source = ./../../lazygit/config.yml;
    ".config/alacritty".source = ./../../alacritty;
    ".config/rofi".source = ./../../rofi;
    ".config/btop".source = ./../../btop;
    ".config/swaync".source = ./../../swaync;
    ".config/waybar".source = ./../../waybar;
    ".config/hypr".source = ./../../hypr;
    ".config/foot".source = ./../../foot;
    ".config/xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;
    '';
    ".icons/stubbe" = {
      source = "${pkgs.vimix-icon-theme}/share/icons/Vimix-black-dark";
    };
    ".themes/stubbe" = {
      source = "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
    };
  };
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = "1";
    NIXPKGS_ALLOW_INSECURE = "1";
    NIXOS_OZONE_WL = "1";
    EDITOR = "${pkgs.neovim}/bin/nvim";
    DISPLAY = ":0";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    GOROOT = "${config.home.homeDirectory}/.go";
    GOPATH = "${config.home.homeDirectory}/go";
    DEPLOYER_REMOTE_USER = "abs";
    GTK_THEME = "stubbe";
  };

  xdg.configFile."environment.d/envvars.conf".text = ''
    PATH="${config.home.homeDirectory}/.nix-profile/bin:$PATH"
  '';

  home.activation.stubbePostBuild = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/.tmux/plugins/tpm" ]; then
      ${pkgs.git}/bin/git clone --quiet https://github.com/tmux-plugins/tpm ${config.home.homeDirectory}/.tmux/plugins/tpm
    fi
    rm -rf "${config.home.homeDirectory}/.config/nvim"
    ln -sf "${config.home.homeDirectory}/.stubbe/src/nvim" "${config.home.homeDirectory}/.config/nvim"
    mkdir -p "${config.home.homeDirectory}/.config/lazygit"
    cat <<EOF > "${config.home.homeDirectory}/.config/lazygit/state.yml"
    lastupdatecheck: 0
    startuppopupversion: 5
    lastversion: ${pkgs.lazygit.version}
    customcommandshistory: []
    hidecommandlog: false
    ignorewhitespaceindiffview: true
    diffcontextsize: 3
    renamesimilaritythreshold: 50
    localbranchsortorder: recency
    remotebranchsortorder: alphabetical
    gitlogorder: topo-order
    gitlogshowgraph: always
    EOF
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
        ExecStart =
          "${config.home.homeDirectory}/.stubbe/src/hypr/scripts/wait_for_power_profiles.sh";
        Restart = "no";
      };
    };
  };

  gtk = {
    enable = true;
    iconTheme = { name = "stubbe"; };
    theme = { name = "stubbe"; };
  };

  qt = {
    enable = true;
    platformTheme = { name = "gtk3"; };
  };

  programs.home-manager.enable = true;
}
