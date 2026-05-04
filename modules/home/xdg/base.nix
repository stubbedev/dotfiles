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
        ]
        // homeLib.xdgSourceWith "waybar" {
          onChange = ''
            if command -v systemctl >/dev/null 2>&1; then
              if systemctl --user is-active --quiet waybar.service 2>/dev/null; then
                systemctl --user restart waybar.service || true
              fi
            fi
          '';
        };

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

      # Default file manager for D-Bus / xdg-open / portal callers.
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "inode/directory" = "pcmanfm.desktop";
          "x-scheme-handler/file" = "pcmanfm.desktop";
        };
      };
    };
}
