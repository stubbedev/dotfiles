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
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "inode/directory" = "pcmanfm.desktop";
          "x-scheme-handler/file" = "pcmanfm.desktop";
          "x-scheme-handler/http" = "com.google.Chrome.desktop";
          "x-scheme-handler/https" = "com.google.Chrome.desktop";
          "x-scheme-handler/about" = "com.google.Chrome.desktop";
          "x-scheme-handler/unknown" = "com.google.Chrome.desktop";
          "text/html" = "com.google.Chrome.desktop";
          "application/xhtml+xml" = "com.google.Chrome.desktop";
        };
      };
    };
}
