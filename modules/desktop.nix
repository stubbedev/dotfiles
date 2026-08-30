# The desktop-environment plumbing that is not the compositor and not the
# shell: D-Bus, MIME defaults, the file manager, and the handful of GUI
# utilities a workstation needs.
#
# MIME defaults exist on both sides on purpose: the system-wide
# /etc/xdg/mimeapps.list is the fallback for anything without a per-user entry,
# and the per-user list overrides it. The type lists are shared here so the two
# can never disagree about which types mpv or imv own.
_:
let
  # mpv opens every video format; imv every still image (svg is left to the
  # browser). Shared by the system-wide fallback list and the per-user one, so
  # the two can never disagree.
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
      # dbus-broker is the modern, faster D-Bus implementation: lower latency,
      # structured journal logging, kdbus-style design without the kernel
      # module. A drop-in replacement for the legacy dbus-daemon.
      services.dbus.implementation = "broker";

      # ~200 MB of NixOS option HTML / docbook XML in the system closure.
      # search.nixos.org and `man configuration.nix` (still kept by
      # documentation.man.enable) cover the same ground.
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
    let
      # vifm's palenight highlight groups, as `group = "<cterm> <fg> <bg>"`.
      # The literal block this replaces was aligned with hand-placed tabs, so
      # the columns drifted with the length of the group name; here the
      # renderer pads and the blank lines that group related entries are the
      # `null` rows.
      vifmHighlight = [
        { Border = "none default default"; }
        null
        { TopLine = "none 002 default"; }
        { TopLineSel = "bold 002 default"; }
        null
        { Win = "none 251 default"; }
        { Directory = "bold 004 default"; }
        { CurrLine = "bold,inverse default default"; }
        { OtherLine = "bold default default"; }
        { Selected = "none 003 008"; }
        null
        { JobLine = "bold 251 008"; }
        { StatusLine = "none 008 default"; }
        { ErrorMsg = "bold 001 default"; }
        { WildMenu = "bold 015 008"; }
        { CmdLine = "none 007 default"; }
        null
        { Executable = "bold 002 default"; }
        { Link = "bold 006 default"; }
        { BrokenLink = "bold 001 default"; }
        { Device = "bold,standout 000 011"; }
        { Fifo = "none 003 default"; }
        { Socket = "bold 005 default"; }
      ];
      renderHighlight =
        entry:
        if entry == null then
          ""
        else
          let
            group = builtins.head (lib.attrNames entry);
            parts = lib.splitString " " entry.${group};
            pad = n: str: str + lib.concatStrings (lib.genList (_: " ") (lib.max 1 (n - lib.stringLength str)));
          in
          "highlight ${pad 14 group}${pad 22 "cterm=${builtins.elemAt parts 0}"}"
          + "${pad 18 "ctermfg=${builtins.elemAt parts 1}"}ctermbg=${builtins.elemAt parts 2}";

      # Upstream's org.remmina.Remmina.desktop bakes absolute /nix/store
      # paths into Exec=, so launching from the menu would bypass the
      # nixGL wrapper. Provide a replacement whose Exec= uses the bare
      # command name; symlinkJoin first-wins ensures it shadows upstream's.
      remminaDesktop = pkgs.makeDesktopItem {
        name = "org.remmina.Remmina";
        desktopName = "Remmina";
        genericName = "Remote Desktop Client";
        comment = "Connect to remote desktops via RDP, VNC, SPICE, NX, XDMCP, SSH";
        exec = "remmina";
        icon = "org.remmina.Remmina";
        type = "Application";
        categories = [
          "GTK"
          "Network"
          "RemoteAccess"
        ];
        mimeTypes = [
          "application/x-remmina"
          "x-scheme-handler/rdp"
          "x-scheme-handler/spice"
          "x-scheme-handler/vnc"
          "x-scheme-handler/remmina"
        ];
        startupNotify = true;
        terminal = false;
        actions = {
          new = {
            name = "Create a New Connection Profile";
            exec = "remmina --new";
          };
          kiosk = {
            name = "Start Remmina in Kiosk mode";
            exec = "remmina --kiosk";
          };
          minimized = {
            name = "Start Remmina Minimized";
            exec = "remmina --icon";
          };
        };
      };
    in
    lib.mkIf config.features.desktop {
      home.packages =
        with pkgs;
        [
          # Network management (GUI applets)
          networkmanagerapplet
          networkmanager-openconnect

          # Bluetooth GUI. The privileged half is in modules/bluetooth.nix.
          blueman

          # Logitech Unifying/Bolt peripherals (battery, DPI, per-device rules).
          # Needs the udev rules from hardware.logitech.wireless on NixOS.
          solaar

          # Monitor brightness (brightnessctl ships from modules/wayle.nix,
          # whose bar scroll actions are its consumer)
          ddcutil

          # Clipboard (stored by the hyprland.lua wl-paste watcher, browsed
          # via the SUPER+V rofi bind)
          cliphist

          # `secret-tool`, for scripts that reach the keyring from the CLI.
          libsecret

          util-linux

          # File managers
          yazi
          pcmanfm
        ]
        ++ [
          # Remote desktop. Upstream's org.remmina.Remmina.desktop bakes absolute
          # store paths into Exec=, so launching from the menu would bypass the
          # nixGL wrapper — hence the replacement desktop item above, which
          # symlinkJoin's first-wins ordering makes shadow upstream's.
          (config.stubbe.gfx.bundle {
            pkg = pkgs.remmina;
            exes = [
              "remmina"
              "remmina-file-wrapper"
            ];
            extraPaths = [ remminaDesktop ];
          })
        ]
        # gvfs + udisks2 are user-installed only off NixOS; on NixOS they come
        # from services.{gvfs,udisks2}.enable in modules/storage.nix.
        ++ lib.optionals (config.host.platform != "nixos") [
          pkgs.gvfs
          pkgs.udisks2
        ];

      programs.vifm = {
        enable = true;
        extraConfig = ''
          " palenight color scheme for vifm

          " Reset all styles first
          highlight clear

          ${lib.concatMapStringsSep "\n" renderHighlight vifmHighlight}
        '';
      };

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

          # Hide the system Nautilus entry from rofi — pcmanfm is "Files" now.
          "org.gnome.Nautilus" = {
            name = "Nautilus";
            exec = "nautilus --new-window %U";
            noDisplay = true;
          };
        };

      };

      # pcmanfm rewrites this file at runtime (window geometry, view state),
      # so a store symlink gets replaced by a real file on first run and the
      # next activation refuses to clobber it. Writable copy, re-asserted each
      # switch — same treatment as btop.conf and kdeglobals.
      stubbe.mutable.".config/pcmanfm/default/pcmanfm.conf" = {
        method = "copy";
        source = (pkgs.formats.ini { }).generate "pcmanfm.conf" {
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

      # Defaults for D-Bus / xdg-open / portal callers. The browser default
      # differs per target: Firefox on NixOS, Chrome on standalone HM.
      xdg.mimeApps = {
        enable = true;
        defaultApplications =
          let
            browser =
              if config.host.platform == "nixos" then "firefox.desktop" else "com.google.Chrome.desktop";
          in
          {
            "inode/directory" = "pcmanfm.desktop";
            "x-scheme-handler/file" = "pcmanfm.desktop";
          }
          // mimeDefaults browser lib;
      };

      # Nix's appimageTools wrappers (Electron/AppImage packages) build their
      # FHS sandbox with bubblewrap, and Ubuntu 24.04+ only lets binaries with a
      # matching AppArmor profile create unprivileged user namespaces — so the
      # store bwrap aborts on launch with
      #   bwrap: setting up uid map: Permission denied
      # Whitelisting it (any version) covers every such package at once;
      # children stay unconfined, so a nested Electron chrome-sandbox works too.
      stubbe.setup.bubblewrapApparmor = pkgs.stubbe.apparmorSetup {
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
            ${lib.concatMapStrings pkgs.stubbe.installLink links}

            sudo install -d -m 0755 /var/lib/udisks2

            sudo systemctl daemon-reload
            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules || true
            fi
            sudo systemctl enable --now udisks2.service
          '';
      };
    };
}
