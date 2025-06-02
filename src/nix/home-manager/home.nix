{ config, lib, pkgs, nixGL, ... }:
let nixglWrapper = builtins.getEnv "NIXGL_WRAPPER";
in {
  nixGL = {
    packages = nixGL.packages;
    defaultWrapper = nixglWrapper;
  };

  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";
  home.stateVersion = "25.05";

  home.packages = (import ./pkgs/app.nix { inherit pkgs config; })
    ++ (import ./pkgs/system.nix { inherit pkgs config; })
    ++ (import ./pkgs/util.nix { inherit pkgs; });

  imports = [ ./programs/git.nix ];

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

  xdg.configFile."environment.d/envvars.conf".text = ''
    PATH="$HOME/.nix-profile/bin:$PATH"
  '';

  home.activation.stubbePostBuild = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone --quiet https://github.com/tmux-plugins/tpm "$HOME"/.tmux/plugins/tpm
    fi
    rm -rf "$HOME/.config/nvim" && ln -sf "$HOME/.stubbe/src/nvim" "$HOME/.config/nvim"
    mkdir -p "$HOME/.config/lazygit" && echo \
    "lastupdatecheck: 0
    startuppopupversion: 5
    customcommandshistory: []
    hidecommandlog: false
    ignorewhitespaceindiffview: true
    diffcontextsize: 3
    renamesimilaritythreshold: 50
    localbranchsortorder: recency
    remotebranchsortorder: alphabetical
    gitlogorder: topo-order
    gitlogshowgraph: always" \
    > "$HOME/.config/lazygit/state.yml"
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

  gtk = {
    enable = true;
    iconTheme = {
      name = "Tela-circle";
      package = pkgs.tela-circle-icon-theme;
    };
  };

  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  programs.home-manager.enable = true;
}
