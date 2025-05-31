{ config, pkgs, ... }:

let
  pinnedLuaPkgs = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/21808d22b1cda1898b71cf1a1beb524a97add2c4.tar.gz";
  }) {};
in

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "stubbe";
  home.homeDirectory = "/home/stubbe";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    pkgs.nh
    pkgs.fd
    pkgs.zsh
    pkgs.nix-zsh-completions
    pkgs.curl
    pkgs.wget
    pkgs.neovim
    pkgs.tmux
    pkgs.git
    pkgs.gnugrep
    pkgs.bat
    pkgs.fzf
    pkgs.eza
    pkgs.htop
    pkgs.btop
    pkgs.jless
    pkgs.ripgrep
    pkgs.lazygit
    pkgs.lazydocker
    pkgs.podman
    pkgs.dbeaver-bin
    pkgs.air
    pkgs.gopass
    pkgs.gotools
    pkgs.jujutsu
    pkgs.tree-sitter
    pkgs.nodejs
    pkgs.bun
    pkgs.yarn
    pkgs.deno
    pkgs.jetbrains-toolbox
    pkgs.hyprland
    pkgs.hyprshot
    pkgs.hyprlock
    pkgs.hyprlang
    pkgs.hyprkeys
    pkgs.hypridle
    pkgs.hyprpaper
    pkgs.hyprsunset
    pkgs.hyprpicker
    pkgs.hyprnotify
    pkgs.hyprcursor
    pkgs.hyprpolkitagent
    pkgs.hyprutils
    pkgs.hyprsysteminfo
    pkgs.dunst
    pkgs.waybar
    pkgs.swaynotificationcenter
    pkgs.adwaita-icon-theme
    pkgs.adwaita-fonts
    pkgs.adwaita-qt
    pkgs.adwaita-qt6
    pkgs.rofi-wayland
    pkgs.xdg-desktop-portal
    pkgs.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-wlr
    pkgs.imagemagick
    pkgs.exiftool
    pkgs.ffmpeg-full
    pkgs.dcraw
    pkgs.libraw
    pkgs.libreoffice
    pkgs.librsvg
    pkgs.zip
    pkgs.ghostscript
    pkgs.unzip
    pkgs.p7zip
    pkgs.libsForQt5.layer-shell-qt
    pkgs.clipman
    pkgs.cliphist
    pkgs.wl-clip-persist
    pkgs.ghostty
		pinnedLuaPkgs.lua
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/stubbe/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
    DISPLAY = ":1";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    DEPLOYER_REMOTE_USER = "abs";
    NIXPKGS_ALLOW_UNFREE = 1;
    NIXPKGS_ALLOW_INSECURE = 1;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

