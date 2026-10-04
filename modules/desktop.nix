_:
let
  mimeDefaults =
    browser: lib:
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
    {
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;
      "text/html" = browser;
      "application/xhtml+xml" = browser;
    }
    // lib.genAttrs videoTypes (_: "mpv.desktop")
    // lib.genAttrs imageTypes (_: "imv.desktop");
in
{
  flake.modules.nixos.desktop =
    { lib, ... }:
    {
      services.dbus.implementation = "broker";

      documentation.nixos.enable = false;

      xdg.mime.defaultApplications = mimeDefaults "firefox.desktop" lib;

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
          networkmanagerapplet
          networkmanager-openconnect

          blueman

          solaar

          ddcutil

          cliphist

          libsecret

          util-linux

          pcmanfm
        ]
        ++ lib.optionals (config.host.platform != "nixos") [
          pkgs.gvfs
          pkgs.udisks2
        ];

      xdg = {
        desktopEntries = {
          # Shown as "Files" in rofi. DBusActivatable is omitted so rofi
          # launches via Exec only — keeping it true makes rofi open two
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
        defaultApplications =
          let
            browser =
              if config.host.platform == "nixos" then "firefox.desktop" else "com.google.Chrome.desktop";
          in
          {
            "x-scheme-handler/http" = browser;
            "x-scheme-handler/https" = browser;
            "x-scheme-handler/about" = browser;
            "x-scheme-handler/unknown" = browser;
            "text/html" = browser;
            "application/xhtml+xml" = browser;
            "inode/directory" = "pcmanfm.desktop";
            "x-scheme-handler/file" = "pcmanfm.desktop";
            "video/*" = "mpv.desktop";
            "image/*" = "imv.desktop";
          };
      };

      # appimageTools wrappers build their FHS sandbox with bubblewrap, which
      # Ubuntu 24.04+ blocks without a matching AppArmor profile.
      stubbe.setup.bubblewrapApparmor = pkgs.stubbe.setup.apparmor {
        appName = "Nix bubblewrap (AppImage/FHS sandbox)";
        profileName = "nix-bubblewrap";
        programGlob = "/nix/store/*/bin/bwrap";
      };

      # udisks2 is a Nix package here, but its daemon has to be reachable from
      # the SYSTEM bus, which never looks in ~/.nix-profile.
      stubbe.setup.udisks = lib.mkIf (config.host.platform != "nixos") {
        privileged = true;
        title = "Installing udisks2 system integration (removable media)";
        body = ''
          Symlinks udisks2's systemd unit, dbus policy + activation, polkit
          policy, udev rules, and default config from the Nix store into
          /etc and /usr/share so the home-manager-installed udisks2 daemon
          can run as a system service. Then reloads systemd/udev and starts
          udisks2.service. gvfs is user-bus and needs nothing privileged.
        '';
        script =
          let
            links = [
              {
                source = "${pkgs.udisks2}/etc/systemd/system/udisks2.service";
                target = "/etc/systemd/system/udisks2.service";
              }
              {
                source = "${pkgs.udisks2}/share/dbus-1/system.d/org.freedesktop.UDisks2.conf";
                target = "/etc/dbus-1/system.d/org.freedesktop.UDisks2.conf";
              }
              {
                source = "${pkgs.udisks2}/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
                target = "/usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
              }
              {
                source = "${pkgs.udisks2}/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
                target = "/usr/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
              }
              {
                source = "${pkgs.udisks2}/lib/udev/rules.d/80-udisks2.rules";
                target = "/etc/udev/rules.d/80-udisks2.rules";
              }
              {
                source = "${pkgs.udisks2}/etc/udisks2/udisks2.conf";
                target = "/etc/udisks2/udisks2.conf";
              }
            ];
          in
          ''
            ${lib.concatMapStrings pkgs.stubbe.setup.link links}

            sudo install -d -m 0755 /var/lib/udisks2

            ${pkgs.stubbe.setup.reloadUnits}
            ${pkgs.stubbe.setup.reloadUdev}
            sudo systemctl enable --now udisks2.service
          '';
      };
    };
}
