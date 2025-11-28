{ config, lib, pkgs, ... }@args:
let
  homeLib = import ./lib.nix { inherit lib; };
  constants = import ./constants.nix { inherit config; };

  homePackages = homeLib.safeLoadPackagesFromDir ./packages args;
  programs = homeLib.loadModulesFromDir ./programs;
in {

  targets.genericLinux.enable = true;
  home = {

    username = constants.user.name;
    homeDirectory = "/home/${constants.user.name}";
    stateVersion = "25.05";
    packages = homePackages;

    file = {
      ".zshrc".text = ''
        if [[ -f "${constants.paths.zsh}/init" ]]; then
          source ${constants.paths.zsh}/init
        fi
      '';
      ".ideavimrc".source = ./../../ideavim/ideavimrc;
      ".tmux.conf".source = ./../../tmux/tmux.conf;

      ".local/bin/open-mail" = {
        text = ''
          #!/usr/bin/env bash
          terminal_emulator="$HOME/.cargo/bin/alacritty"
          if [[ ! -x "$terminal_emulator" ]]; then
            terminal_emulator="${config.home.homeDirectory}/.nix-profile/bin/alacritty"
          fi
          # $terminal_emulator -e ${config.home.homeDirectory}/.nix-profile/bin/neomutt -F ${config.home.homeDirectory}/.config/neomutt/neomuttrc
          $terminal_emulator -e aerc
        '';
        executable = true;
      };

      ".icons/${constants.theme.iconTheme}".source  = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      ".themes/${constants.theme.gtkTheme}".source = "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
      ".w3m".source = ./../../w3m;
    };

    sessionVariables = {
      # Nix configuration
      NIXPKGS_ALLOW_UNFREE = "1";
      NIXPKGS_ALLOW_INSECURE = "1";
      NIXOS_OZONE_WL = "1";

      # Editor and display
      EDITOR = "$HOME/.local/bin/nvim";
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
      GTK_THEME_VARIANT = "dark";
      DEPLOYER_REMOTE_USER = "abs";
    };

    activation = {
      customConfigCleanUp = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (import ./scripts/config-cleanup.nix {
          inherit config pkgs constants;
        });
      customBinInstall = lib.hm.dag.entryAfter [ "customConfigCleanUp" ]
        (import ./scripts/bin-install.nix { inherit config pkgs constants; });
      customShellCompletions = lib.hm.dag.entryAfter [ "customBinInstall" ]
        (import ./scripts/shell-completions.nix {
          inherit config pkgs constants;
        });
    };
  };

  imports = programs;

  # XDG Config files
  xdg.configFile = {
    "lazygit/config.yml".source = ./../../lazygit/config.yml;
    "ghostty".source = ./../../ghostty;
    "alacritty".source = ./../../alacritty;
    "rofi".source = ./../../rofi;
    "btop/themes/catppuccin_frappe.theme".source =
      ./../../btop/themes/catppuccin_frappe.theme;
    "btop/themes/catppuccin_latte.theme".source =
      ./../../btop/themes/catppuccin_latte.theme;
    "btop/themes/catppuccin_macchiato.theme".source =
      ./../../btop/themes/catppuccin_macchiato.theme;
    "btop/themes/catppuccin_mocha.theme".source =
      ./../../btop/themes/catppuccin_mocha.theme;
    "swaync".source = ./../../swaync;
    "sway".source = ./../../sway;
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
    "neomutt/neomuttrc".source = ./../../neomutt/neomuttrc;
    "neomutt/mailcap".source = ./../../neomutt/mailcap;
    "aerc/aerc.conf".source = ./../../aerc/aerc.conf;
    "aerc/binds.conf".source = ./../../aerc/binds.conf;
  };

  systemd.user.services = {
    waybar-reload-on-power-profile = {
      Unit = {
        Description = "Reload Waybar when power-profiles-daemon starts";
        After = [ "graphical-session.target" "power-profiles-daemon.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart =
          "${constants.paths.hypr}/scripts/wait_for_power_profiles.sh";
        Restart = "no";
      };
    };
  };

  programs.home-manager.enable = true;
}
