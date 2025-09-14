{ config, lib, pkgs, ... }@args:
let
  homeLib = import ./lib.nix { inherit lib; };
  constants = import ./constants.nix { inherit config; };

  # Environment-based feature flags with validation
  enableHyprland = builtins.getEnv "USE_HYPRLAND";
  useHyprland = enableHyprland == "true" || enableHyprland == true;
  # Optimized package loading with error handling
  homePackages = homeLib.safeLoadPackagesFromDir ./packages args;
  hyprlandPackages = homeLib.safeLoadPackagesFromDir ./hyprland args;

  # Optimized module imports with conditional loading
  coreModules = homeLib.loadModulesFromDir ./programs;
  serviceModules = homeLib.loadModulesFromDir ./services;

  allModules = coreModules ++ serviceModules;
in {
  targets.genericLinux.enable = true;

  home.username = constants.user.name;
  home.homeDirectory = "/home/${constants.user.name}";
  home.stateVersion = "25.05";
  home.packages = homePackages ++ hyprlandPackages;

  imports = allModules;

  home.file = {
    ".zshrc".text = ''
      if [[ -f "${constants.paths.zsh}/init" ]]; then
        source ${constants.paths.zsh}/init
      fi

    '';
    ".ideavimrc".source = ./../../ideavim/ideavimrc;
    ".tmux.conf".source = ./../../tmux/tmux.conf;

    # Theme files
    ".icons/${constants.theme.iconTheme}" = {
      source = "${pkgs.vimix-icon-theme}/share/icons/Vimix-black-dark";
    };
    ".themes/${constants.theme.gtkTheme}" = {
      source = "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
    };
  };

  # XDG Config files 
  xdg.configFile = {
    "lazygit/config.yml".source = ./../../lazygit/config.yml;
    "alacritty".source = ./../../alacritty;
    "rofi".source = ./../../rofi;
    "btop/themes/catppuccin_frappe.theme".source = ./../../btop/themes/catppuccin_frappe.theme;
    "btop/themes/catppuccin_latte.theme".source = ./../../btop/themes/catppuccin_latte.theme;
    "btop/themes/catppuccin_macchiato.theme".source = ./../../btop/themes/catppuccin_macchiato.theme;
    "btop/themes/catppuccin_mocha.theme".source = ./../../btop/themes/catppuccin_mocha.theme;
    "swaync".source = ./../../swaync;
    "waybar".source = ./../../waybar;
    "hypr".source = ./../../hypr;
    "foot".source = ./../../foot;
    "opencode/opencode.json".source = ./../../opencode/opencode.json;
    "opencode/themes/catppuccin-mocha.json".source =
      ./../../opencode/catppuccin-mocha.json;

    "xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;kde;
    '';

    "environment.d/envvars.conf".text = ''
      PATH="${config.home.homeDirectory}/.nix-profile/bin:$PATH"
    '';
  };

  home.sessionVariables = {
    # Nix configuration
    NIXPKGS_ALLOW_UNFREE = "1";
    NIXPKGS_ALLOW_INSECURE = "1";
    NIXOS_OZONE_WL = "1";

    # Editor and display
    EDITOR = "${pkgs.neovim}/bin/nvim";
    DISPLAY = ":0";

    # Paging and documentation
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    PAGER = "${pkgs.more}/bin/more";

    # Go configuration
    GOROOT = "${config.home.homeDirectory}/.go";
    GOPATH = "${config.home.homeDirectory}/go";

    # Theme and custom variables
    GTK_THEME = constants.theme.gtkTheme;
    DEPLOYER_REMOTE_USER = "abs";
  };

  home.activation.customConfigCleanUp =
    lib.hm.dag.entryAfter [ "writeBoundary" ]
    (import ./scripts/config-cleanup.nix { inherit config pkgs constants; });
  home.activation.customBinInstall =
    lib.hm.dag.entryAfter [ "customConfigCleanUp" ]
    (import ./scripts/bin-install.nix { inherit config pkgs; });
  home.activation.customShellCompletions =
    lib.hm.dag.entryAfter [ "customBinInstall" ]
    (import ./scripts/shell-completions.nix { inherit config pkgs constants; });

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
          "${constants.paths.hypr}/scripts/wait_for_power_profiles.sh";
        Restart = "no";
      };
    };
  };

  gtk = {
    enable = true;
    iconTheme = { name = constants.theme.iconTheme; };
    theme = { name = constants.theme.gtkTheme; };
  };

  qt = {
    enable = true;
    platformTheme = { name = "gtk3"; };
  };

  programs.home-manager.enable = true;
}
