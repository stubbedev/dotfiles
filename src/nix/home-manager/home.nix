{ config, lib, pkgs, ... }@args:
let
  homeLib = import ./lib.nix { inherit lib; };
  constants = import ./constants.nix { inherit config; };

  homePackages = homeLib.safeLoadPackagesFromDir ./packages args;
  programs = homeLib.loadModulesFromDir ./programs;

  # Load VPN scripts dynamically
  vpnScripts = homeLib.loadVpnScripts ./../../vpn;
  vpnConfigs = homeLib.loadVpnConfigs ./../../vpn;

  # Auto-detect NVIDIA GPU by checking if the driver is loaded
  hasNvidia = builtins.pathExists /proc/driver/nvidia/version;

  # Detect OS distribution
  osReleasePath = /etc/os-release;
  osReleaseContent = if builtins.pathExists osReleasePath then
    builtins.readFile osReleasePath
  else
    "";
  isFedora = builtins.match ".*ID=fedora.*" osReleaseContent != null;

  # Determine driver library paths based on OS
  driverPaths = if isFedora then {
    libgl = "/usr/lib64/dri";
    gbm = "/usr/lib64/gbm";
  } else {
    libgl = "/usr/lib/dri";
    gbm = "/usr/lib/gbm";
  };
in {

  targets.genericLinux = {
    enable = true;
    nixGL = {
      packages = pkgs.nixgl;
      defaultWrapper = if hasNvidia then "nvidia" else "mesa";
    };
  };
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

          # Find terminal emulator
          terminal_emulator="$HOME/.cargo/bin/alacritty"
          if [[ ! -x "$terminal_emulator" ]]; then
            terminal_emulator="${config.home.homeDirectory}/.nix-profile/bin/alacritty"
          fi

          # Check if Hyprland is active and hyprctl is available
          if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
            # Use hyprctl dispatch exec to launch in the current workspace
            hyprctl dispatch exec "$terminal_emulator -e aerc"
          else
            # Launch normally
            $terminal_emulator -e aerc
          fi
        '';
        executable = true;
      };
      ".local/bin/unsubscribe-mail".source = ./../../aerc/scripts/unsubscribe;

      ".icons/${constants.theme.iconTheme}".source =
        "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark";
      ".themes/${constants.theme.gtkTheme}".source =
        "${pkgs.rose-pine-gtk-theme}/share/themes/rose-pine";
      ".w3m".source = ./../../w3m;
    } // vpnScripts;

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
      customBinInstall = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (import ./scripts/bin-install.nix { inherit config pkgs constants; });
      customShellCompletions = lib.hm.dag.entryAfter [ "customBinInstall" ]
        (import ./scripts/shell-completions.nix {
          inherit config pkgs constants;
        });
      customConfigCleanUp = lib.hm.dag.entryAfter [ "customShellCompletions" ]
        (import ./scripts/config-cleanup.nix {
          inherit config pkgs constants;
        });

      # Restart PipeWire after audio config changes
      restartPipewire = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
      '';
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

    # Copy individual hypr config files (not as a directory to allow overriding env.conf)
    "hypr/hypridle.conf".source = ./../../hypr/hypridle.conf;
    "hypr/hyprland.conf".source = ./../../hypr/hyprland.conf;
    "hypr/hyprlock.conf".source = ./../../hypr/hyprlock.conf;
    "hypr/hyprpaper.conf".source = ./../../hypr/hyprpaper.conf;
    "hypr/hyprsunset.conf".source = ./../../hypr/hyprsunset.conf;
    "hypr/keybinds.conf".source = ./../../hypr/keybinds.conf;
    "hypr/monitors.conf".source = ./../../hypr/monitors.conf;
    "hypr/settings.conf".source = ./../../hypr/settings.conf;
    "hypr/theme.conf".source = ./../../hypr/theme.conf;
    "hypr/windowrule.conf".source = ./../../hypr/windowrule.conf;
    "hypr/scripts".source = ./../../hypr/scripts;

    # Generate dynamic Hyprland env.conf based on system detection
    "hypr/env.conf" = {
      text = ''
        env = XDG_CURRENT_DESKTOP,Hyprland
        env = XDG_SESSION_TYPE,wayland
        env = XDG_SESSION_DESKTOP,Hyprland
        env = XCURSOR_THEME,Adwaita
        env = GTK_CURSORS,Adwaita
        env = XCURSOR_SIZE,24
        env = GTK_THEME,Adwaita-dark
        env = PATH,$HOME/.cargo/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin

        # GPU driver configuration (auto-detected: ${
          if hasNvidia then "NVIDIA" else "Mesa"
        })
        ${lib.optionalString hasNvidia ''
          env = __GLX_VENDOR_LIBRARY_NAME,nvidia
          env = LIBVA_DRIVER_NAME,nvidia
        ''}
      '';
    };
    "opencode/opencode.json".source = ./../../opencode/opencode.json;
    "opencode/AGENTS.md".source = ./../../opencode/AGENTS.md;
    "opencode/themes/catppuccin-mocha.json".source =
      ./../../opencode/catppuccin-mocha.json;

    "xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;kde;
    '';

    "environment.d/envvars.conf".text = ''
      PATH="${config.home.homeDirectory}/.nix-profile/bin:$PATH"
    '';
    "aerc/aerc.conf".source = ./../../aerc/aerc.conf;
    "aerc/binds.conf".source = ./../../aerc/binds.conf;

    # PipeWire audio configuration for USB docks with KVM switches
    "pipewire/pipewire.conf.d/99-usb-dock.conf".source =
      ./../../pipewire/pipewire.conf.d/99-usb-dock.conf;
    "pipewire/pipewire-pulse.conf.d/99-usb-dock.conf".source =
      ./../../pipewire/pipewire-pulse.conf.d/99-usb-dock.conf;

    # PulseAudio client config for flatpak apps (prevents audio popping)
    "pulse/client.conf".source = ./../../pipewire/pulse-client.conf;

    # WirePlumber ALSA configuration for USB dock stability
    "wireplumber/main.lua.d/51-alsa-usb-dock.lua".source =
      ./../../wireplumber/main.lua.d/51-alsa-usb-dock.lua;
  } // vpnConfigs;

  systemd.user.services = {
    await-powerprofile = {
      Unit = {
        Description = "Reload Waybar when power-profiles-daemon starts";
        After = [ "default.target" "power-profiles-daemon.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart =
          "${constants.paths.hypr}/scripts/service.await.sh power-profiles-daemon.service";
        Restart = "no";
      };
    };
    await-bluetooth = {
      Unit = {
        Description = "Reload Waybar when bluetooth starts";
        After = [ "default.target" "bluetooth.service" ];
      };
      Install = { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "oneshot";
        ExecStart =
          "${constants.paths.hypr}/scripts/service.await.sh bluetooth.service";
        Restart = "no";
      };
    };
  };

  programs.home-manager.enable = true;

  nix = {
    package = pkgs.nix;
    settings = {
      # Prefer binary caches to avoid compilation
      substituters =
        [ "https://cache.nixos.org" "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
}
