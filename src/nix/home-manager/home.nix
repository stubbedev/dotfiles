{ config, lib, pkgs, nixGL, ... }@args:
let
  nixglWrapper = builtins.getEnv "NIXGL_WRAPPER";
  enableHyprland = builtins.getEnv "USE_HYPRLAND";
  useHyprland = if enableHyprland == "true" || enableHyprland == true then true else false;
  homePackages = builtins.concatLists
    (map (file: import (./packages + "/${file}") args)
      (builtins.filter (f: builtins.match ".*\\.nix$" f != null)
        (builtins.attrNames (builtins.readDir ./packages))));
  hyprlandPackages = builtins.concatLists
      (map (file: import (./hyprland + "/${file}") args)
        (builtins.filter (f: builtins.match ".*\\.nix$" f != null)
          (builtins.attrNames (builtins.readDir ./hyprland))));
  importedProgramsAndServices = map (f: ./programs + "/${f}")
    (builtins.filter (f: builtins.match ".*\\.nix$" f != null)
      (builtins.attrNames (builtins.readDir ./programs)))
    ++ map (f: ./services + "/${f}")
    (builtins.filter (f: builtins.match ".*\\.nix$" f != null)
      (builtins.attrNames (builtins.readDir ./services)));
in {
  nixGL = {
    packages = nixGL.packages;
    defaultWrapper = nixglWrapper;
  };

  targets.genericLinux.enable = true;

  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";
  home.stateVersion = "25.05";
  home.packages = if useHyprland then homePackages ++ hyprlandPackages else homePackages;

  imports = importedProgramsAndServices;

  home.file = {
    ".zshrc".text = ''
      if [[ -f "${config.home.homeDirectory}/.stubbe/src/zsh/init" ]]; then
        source ${config.home.homeDirectory}/.stubbe/src/zsh/init
      fi

    '';
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
    ".config/opencode/opencode.json".source = ./../../opencode/opencode.json;
    ".config/opencode/themes/catppuccin-mocha.json".source = ./../../opencode/catppuccin-mocha.json;
    ".config/xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;kde;
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
    PAGER = "${pkgs.more}/bin/more";
  };

  xdg.configFile."environment.d/envvars.conf".text = ''
    PATH="${config.home.homeDirectory}/.nix-profile/bin:$PATH"
  '';

  home.activation.stubbePostBuild = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -f ${config.home.homeDirectory}/.zcompdump > /dev/null 2>&1
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
    ${pkgs.gh}/bin/gh extension install github/gh-copilot > /dev/null 2>&1
    ${pkgs.gh}/bin/gh extension upgrade github/gh-copilot > /dev/null 2>&1
    ${pkgs.gh}/bin/gh completion -s zsh > ${config.home.homeDirectory}/.stubbe/src/zsh/fpaths.d/_gh
    ${pkgs.bun}/bin/bun install opencode-ai@latest --global > /dev/null 2>&1
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
    enable = useHyprland;
    iconTheme = { name = "stubbe"; };
    theme = { name = "stubbe"; };
  };

  qt = {
    enable = useHyprland;
    platformTheme = { name = "gtk3"; };
  };

  programs.home-manager.enable = true;
}
