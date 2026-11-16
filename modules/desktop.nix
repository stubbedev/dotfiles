{ lib, ... }:
let
  browserDesktopIds = {
    firefox = "firefox.desktop";
    chrome = "com.google.Chrome.desktop";
  };
  videoPlayer = "mpv.desktop";
  imageViewer = "imv.desktop";
  fileManager = "pcmanfm.desktop";

  browserHandlers =
    browser:
    lib.genAttrs [
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
      "text/html"
      "application/xhtml+xml"
    ] (_: browser);

  mimeDefaults =
    browser:
    let
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
    browserHandlers browser
    // lib.genAttrs videoTypes (_: videoPlayer)
    // lib.genAttrs imageTypes (_: imageViewer);
in
{
  flake.modules.nixos.desktop =
    { config, ... }:
    {
      services.dbus.implementation = "broker";

      documentation.nixos.enable = false;

      xdg.mime.defaultApplications = mimeDefaults browserDesktopIds.${config.host.browser};
    };

  flake.modules.homeManager.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.packages =
        with pkgs;
        [
          networkmanager-openconnect

          solaar

          ddcutil

          util-linux
          xdg-utils

          pcmanfm
        ]
        ++ lib.optionals config.features.slack [
          (pkgs.stubbe.wrapPackage {
            pkg = pkgs.slack;
            flags = [ "--disable-setuid-sandbox" ];
          })
        ];

      xdg = {
        desktopEntries = {
          # Shown as "Files" in the launcher. DBusActivatable is omitted so it
          # launches via Exec only — keeping it true makes the launcher open two
          # windows (one via D-Bus, one via Exec).
          pcmanfm = {
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

          "org.gnome.Nautilus" = {
            name = "Nautilus";
            exec = "nautilus --new-window %U";
            noDisplay = true;
          };
        };

      };

      # pcmanfm rewrites this file at runtime, so a store symlink is replaced by
      # a real file on first run and the next activation refuses to clobber it.
      stubbe.mutable.".config/pcmanfm/default/pcmanfm.conf" = {
        method = "copy";
        source = pkgs.stubbe.gen.ini "pcmanfm.conf" {
          config.bm_open_method = 0;
          volume = {
            mount_on_startup = 1;
            mount_removable = 1;
            autorun = 1;
          };
          ui = {
            always_show_tabs = 0;
            max_tab_chars = 32;
            win_width = 640;
            win_height = 480;
            maximized = 1;
            splitter_pos = 150;
            media_in_new_tab = 0;
            desktop_folder_new_win = 0;
            change_tab_on_drop = 1;
            close_on_unmount = 1;
            focus_previous = 0;
            side_pane_mode = "places";
            view_mode = "list";
            show_hidden = 1;
            sort = "name;ascending;";
            toolbar = "newtab;navigation;home;";
            show_statusbar = 1;
            pathbar_mode_buttons = 0;
          };
        };
      };

      xdg.mimeApps = {
        enable = true;
        # Glob keys expand against shared-mime-info at eval time; exact keys
        # would keep precedence over a glob match. The NixOS half above keeps
        # the explicit list: xdg.mime has no glob support.
        defaultApplications = browserHandlers browserDesktopIds.${config.host.browser} // {
          "inode/directory" = fileManager;
          "x-scheme-handler/file" = fileManager;
          "video/*" = videoPlayer;
          "image/*" = imageViewer;
        };
      };
    };
}
