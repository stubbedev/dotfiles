_: {
  flake.modules.homeManager.xdgBase =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile = homeLib.xdgSources [
        "lazygit/config.yml"
        "alacritty"
        "rofi"
        "btop/themes/catppuccin_frappe.theme"
        "btop/themes/catppuccin_latte.theme"
        "btop/themes/catppuccin_macchiato.theme"
        "btop/themes/catppuccin_mocha.theme"
        "swaync"
        "waybar"
      ];

      # Override the system Nautilus desktop entry to remove DBusActivatable,
      # which causes Rofi to open two windows (one via D-Bus, one via Exec).
      xdg.desktopEntries."org.gnome.Nautilus" = {
        name = "Files";
        comment = "Access and organize files";
        exec = "nautilus --new-window %U";
        icon = "org.gnome.Nautilus";
        terminal = false;
        categories = [
          "GNOME"
          "GTK"
          "Utility"
          "Core"
          "FileManager"
        ];
        mimeType = [
          "inode/directory"
          "application/x-7z-compressed"
          "application/x-7z-compressed-tar"
          "application/x-bzip"
          "application/x-bzip-compressed-tar"
          "application/x-compress"
          "application/x-compressed-tar"
          "application/x-cpio"
          "application/x-gzip"
          "application/x-lha"
          "application/x-lzip"
          "application/x-lzip-compressed-tar"
          "application/x-lzma"
          "application/x-lzma-compressed-tar"
          "application/x-tar"
          "application/x-tarz"
          "application/x-xar"
          "application/x-xz"
          "application/x-xz-compressed-tar"
          "application/zip"
          "application/gzip"
          "application/bzip2"
          "application/x-bzip2-compressed-tar"
          "application/vnd.rar"
          "application/zstd"
          "application/x-zstd-compressed-tar"
        ];
        settings = {
          Keywords = "folder;manager;explore;disk;filesystem;nautilus;";
          StartupNotify = "true";
          X-GNOME-UsesNotifications = "true";
        };
      };
    };
}
