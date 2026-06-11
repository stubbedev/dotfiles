_: {
  flake.modules.homeManager.xdgBase =
    {
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      xdg.configFile =
        homeLib.xdgSources [
          "lazygit/config.yml"
          "alacritty"
          "pcmanfm/default/pcmanfm.conf"
          "rofi"
          "btop/themes/catppuccin_frappe.theme"
          "btop/themes/catppuccin_latte.theme"
          "btop/themes/catppuccin_macchiato.theme"
          "btop/themes/catppuccin_mocha.theme"
          "swaync"
          "waybar"
        ];

      # PCManFM desktop entry: shown as "Files" in rofi. DBusActivatable is
      # omitted so rofi launches via Exec only — keeping it true would make
      # rofi open two windows (one via D-Bus, one via Exec).
      xdg.desktopEntries.pcmanfm = {
        name = "Files";
        genericName = "File Manager";
        comment = "Browse the file system and manage the files";
        exec = "pcmanfm %U";
        icon = "system-file-manager";
        terminal = false;
        categories = [
          "GTK"
          "Utility"
          "Core"
          "FileManager"
        ];
        mimeType = [
          "inode/directory"
          "x-scheme-handler/trash"
        ];
        settings = {
          Keywords = "folder;manager;explore;disk;filesystem;";
          StartupNotify = "true";
        };
      };

      # Hide the system Nautilus entry from rofi — pcmanfm is "Files" now.
      xdg.desktopEntries."org.gnome.Nautilus" = {
        name = "Nautilus";
        exec = "nautilus --new-window %U";
        noDisplay = true;
      };

      # Default file manager + browser for D-Bus / xdg-open / portal callers.
      # Browser default differs per target: Firefox on NixOS, Chrome on
      # standalone home-manager.
      xdg.mimeApps =
        let
          browser =
            if config.host.platform == "nixos" then
              "firefox.desktop"
            else
              "com.google.Chrome.desktop";
          # mpv is the default opener for all video formats.
          videoTypes = [
            "video/mp4"
            "video/x-matroska"
            "video/webm"
            "video/quicktime"
            "video/x-msvideo"
            "video/mpeg"
            "video/x-flv"
            "video/ogg"
            "video/3gpp"
            "video/3gpp2"
            "video/x-ms-wmv"
            "video/x-ms-asf"
            "video/x-m4v"
            "video/mp2t"
            "video/dv"
            "video/avi"
            "application/x-matroska"
          ];
          # imv is the default opener for still images (svg left to the browser).
          imageTypes = [
            "image/jpeg"
            "image/png"
            "image/gif"
            "image/webp"
            "image/avif"
            "image/tiff"
            "image/bmp"
            "image/heif"
            "image/heic"
            "image/jxl"
            "image/x-icon"
            "image/x-portable-pixmap"
            "image/x-portable-anymap"
          ];
        in
        {
          enable = true;
          defaultApplications = {
            "inode/directory" = "pcmanfm.desktop";
            "x-scheme-handler/file" = "pcmanfm.desktop";
            "x-scheme-handler/http" = browser;
            "x-scheme-handler/https" = browser;
            "x-scheme-handler/about" = browser;
            "x-scheme-handler/unknown" = browser;
            "text/html" = browser;
            "application/xhtml+xml" = browser;
          }
          // lib.genAttrs videoTypes (_: "mpv.desktop")
          // lib.genAttrs imageTypes (_: "imv.desktop");
        };
    };
}
