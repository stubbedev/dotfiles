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
    { lib, pkgs, ... }:
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

      environment.systemPackages = with pkgs; [
        # The custom shell widgets shell out to python3.
        python3
        imgcat
        freerdp
        redis # provides redis-cli
      ];
    };

  flake.modules.homeManager.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
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

          # Monitor brightness
          brightnessctl
          ddcutil

          # Clipboard
          clipman
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
        extraConfig = pkgs.stubbe.text "src/desktop/vifm.vifm";
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

        configFile."pcmanfm/default/pcmanfm.conf".source = pkgs.stubbe.file "src/desktop/pcmanfm.conf";

        # Defaults for D-Bus / xdg-open / portal callers. The browser default
        # differs per target: Firefox on NixOS, Chrome on standalone HM.
        mimeApps = {
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
                src = "${pkgs.udisks2}/etc/systemd/system/udisks2.service";
                dst = "/etc/systemd/system/udisks2.service";
              }
              {
                src = "${pkgs.udisks2}/share/dbus-1/system.d/org.freedesktop.UDisks2.conf";
                dst = "/etc/dbus-1/system.d/org.freedesktop.UDisks2.conf";
              }
              {
                src = "${pkgs.udisks2}/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
                dst = "/usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
              }
              {
                src = "${pkgs.udisks2}/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
                dst = "/usr/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
              }
              {
                src = "${pkgs.udisks2}/lib/udev/rules.d/80-udisks2.rules";
                dst = "/etc/udev/rules.d/80-udisks2.rules";
              }
              {
                src = "${pkgs.udisks2}/etc/udisks2/udisks2.conf";
                dst = "/etc/udisks2/udisks2.conf";
              }
            ];
          in
          ''
            ${lib.concatMapStrings (l: ''
              sudo install -d -m 0755 "$(dirname "${l.dst}")"
              sudo ln -sfT "${l.src}" "${l.dst}"
            '') links}

            sudo install -d -m 0755 /var/lib/udisks2

            sudo systemctl daemon-reload
            if command -v udevadm >/dev/null 2>&1; then
              sudo udevadm control --reload-rules
            fi
            sudo systemctl enable --now udisks2.service
          '';
      };
    };
}
