{ config, ... }:
{
  paths = {
    dotfiles = "${config.home.homeDirectory}/.stubbe";
    zsh = "${config.home.homeDirectory}/.stubbe/src/zsh";
    # home.profileDirectory resolves to /etc/profiles/per-user/$USER under
    # NixOS (useUserPackages) and ~/.nix-profile under standalone HM.
    nixBin = "${config.home.profileDirectory}/bin";
    term = "${config.home.profileDirectory}/bin/alacritty";
    # Desktop wallpaper. Single source of truth: wayle-launch applies it to
    # every monitor at startup (modules/home/scripts.nix), exported as the
    # WALLPAPER session var (modules/home/session-variables.nix) so the
    # per-compositor DRM-hotplug listeners (src/hypr/scripts/monitor.toggle.sh,
    # src/niri/scripts/wallpaper.hotplug.sh) re-apply it on dock without
    # hardcoding the path.
    wallpaper = "${config.home.homeDirectory}/.stubbe/src/wallpapers/ballet.jpg";
  };

  # Theme names referenced across modules. Keep in lockstep with what
  # modules/theme/gtk.nix actually selects.
  theme = {
    icon = "Tela-circle-purple-dark";
    cursor = "Vimix-cursors";
    cursorSize = 24;
    gtk = "catppuccin-mocha-mauve-standard";
    kvantum = "Catppuccin-Mocha-Mauve";
    sddm = "catppuccin-mocha-mauve";
    plymouth = "catppuccin-mocha";
  };
}
