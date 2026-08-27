# Everything that makes the desktop look like one system: the GTK/Qt/icon/cursor
# theme names, the fonts, and the per-toolkit config each one needs.
#
# Every theme NAME comes from `pkgs.stubbe.theme` (flake.lib), so the GTK theme,
# the Kvantum theme, the Qt icon theme, the cursor exported into the session and
# the copy the greeter reads can never disagree.
_: {
  flake.modules.nixos.theming =
    { pkgs, ... }:
    {
      # The HM dconf module writes dconf keys (color-scheme, blueman). On NixOS
      # the dconf service must be enabled system-wide for those to apply —
      # otherwise activation errors with "dconf is not enabled".
      programs.dconf.enable = true;

      # Qt platform theming. qt5ct/qt6ct read the conf files written by the HM
      # half, which delegate widget rendering to Kvantum; Kvantum picks up its
      # theme from ~/.config/Kvantum/kvantum.kvconfig, also written there.
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };

      environment.sessionVariables = {
        # Route GTK apps (notably Firefox) through their Wayland backends so
        # libinput gestures — two-finger scroll, pinch-zoom, swipe
        # back/forward — reach the application instead of being swallowed by
        # XWayland's lack of XInput2 gesture support. MOZ_USE_XINPUT2 covers
        # the X11-fallback path.
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_USE_XINPUT2 = "1";

        # Cursor, system-wide so PAM/login shells and the session manager
        # export it before the compositor starts. The HM half mirrors this.
        XCURSOR_THEME = pkgs.stubbe.theme.cursor;
        XCURSOR_SIZE = toString pkgs.stubbe.theme.cursorSize;
      };

      # Mirrors the font set the HM half installs. On NixOS these must be
      # system-wide so the greeter — which runs before any user session — can
      # render them.
      fonts = {
        packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          font-awesome
          adwaita-fonts
        ];
        fontconfig.enable = true;
      };

      environment.systemPackages = with pkgs; [
        # Provides the Catppuccin-Mocha-Mauve Kvantum theme files. The Qt5/Qt6
        # style plugins are installed into the user profile by the HM half.
        catppuccin-kvantum
        # Cursor theme system-wide (not just home-manager) so it lands in
        # /run/current-system/sw/share/icons — where the greetd greeter, running
        # as the unprivileged `greeter` user that cannot read a 0700 $HOME, can
        # actually find it. Without it the login screen falls back to the huge
        # built-in cursor.
        vimix-cursors
      ];
    };

  flake.modules.homeManager.theming =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      theme = pkgs.stubbe.theme;

      # qt5ct and qt6ct share one ini format. Render once, write to both.
      qtCtConf = ''
        [Appearance]
        color_scheme_path=
        custom_palette=false
        icon_theme=${theme.icon}
        standard_dialogs=default
        style=kvantum

        [Interface]
        activate_item_on_single_click=1
        buttonbox_layout=0
        cursor_flash_time=1000
        dialog_buttons_have_icons=1
        double_click_interval=400
        gui_effects=@Invalid()
        keyboard_scheme=2
        menus_have_icons=true
        show_shortcuts_in_context_menus=true
        stylesheets=@Invalid()
        toolbutton_style=4
        underline_shortcut=1
        wheel_scroll_lines=3
      '';
    in
    lib.mkIf config.features.theming {
      gtk = {
        enable = true;

        theme = {
          name = theme.gtk;
          package = pkgs.catppuccin-gtk.override {
            variant = "mocha";
            accents = [ "mauve" ];
            size = "standard";
          };
        };

        iconTheme = {
          name = theme.icon;
          package = pkgs.tela-circle-icon-theme.override { colorVariants = [ "purple" ]; };
        };

        cursorTheme = {
          name = theme.cursor;
          package = pkgs.vimix-cursors;
          size = theme.cursorSize;
        };

        gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
        gtk4 = {
          theme = null;
          extraConfig.gtk-application-prefer-dark-theme = 1;
        };
      };

      # gtk-theme/icon-theme/cursor-theme are already written by the gtk module
      # above, which sets the same dconf keys — only what it does not cover
      # belongs here, or the definitions conflict.
      dconf.settings = {
        "org/gnome/desktop/interface".color-scheme = "prefer-dark";
        "org/blueman/general".notification-daemon = true;
      };

      # Symlinks fonts from home.packages into ~/.local/share/fonts and runs
      # fc-cache on activation. Without this, fontconfig only sees /usr/share
      # and Nix-installed fonts are invisible on non-NixOS hosts.
      fonts.fontconfig.enable = true;

      home = {
        packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          font-awesome
          adwaita-fonts

          adwaita-icon-theme
          vimix-icon-theme
          hicolor-icon-theme
          gnome-themes-extra # includes the Adwaita-dark GTK theme
          gtk4-layer-shell

          adwaita-qt
          adwaita-qt6
          libsForQt5.qt5ct
          kdePackages.qt6ct
          libsForQt5.qtstyleplugins
          # Kvantum style engine, both Qt majors.
          libsForQt5.qtstyleplugin-kvantum
          kdePackages.qtstyleplugin-kvantum
        ];

        file = {
          ".icons/${theme.cursor}".source = "${pkgs.vimix-cursors}/share/icons/${theme.cursor}";
          # Also under .local/share/icons, for libxcursor lookups that prefer
          # the XDG path (Ubuntu 24.04 libXcursor 1.2.3+).
          ".local/share/icons/${theme.cursor}".source = "${pkgs.vimix-cursors}/share/icons/${theme.cursor}";
          ".local/share/icons/Vimix-dark".source = "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";

          # Flatpak dark-mode overrides. Qt/KDE flatpaks may still have poor
          # contrast: they use the Breeze theme from their own runtime.
          ".local/share/flatpak/overrides/global".source = (pkgs.formats.ini { }).generate "flatpak-global" {
            Context.filesystems = "xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;~/.themes:ro;~/.icons:ro;/nix/store:ro";
            Environment = {
              GTK_THEME = "Adwaita-dark";
              QT_QPA_PLATFORMTHEME = "kde";
              QT_STYLE = "breeze";
              COLOR_SCHEME = "prefer-dark";
              GDK_BACKEND = "wayland,x11";
            };
          };
          # Steam: X11/GLX support under Wayland, plus XDG_RUNTIME_DIR access
          # for XAUTHORITY and Discord RPC.
          ".local/share/flatpak/overrides/com.valvesoftware.Steam" = {
            source = (pkgs.formats.ini { }).generate "flatpak-steam" {
              Context.filesystems = "/run/user/1000";
            };
            force = true;
          };
        };
      };

      xdg.configFile = {
        # The Catppuccin-Mocha-Mauve theme files come from catppuccin-kvantum,
        # a system package on NixOS.
        "Kvantum/kvantum.kvconfig".text = ''
          [General]
          theme=${theme.kvantum}
        '';

        # QT_QPA_PLATFORMTHEME=qt5ct — set system-wide by the NixOS qt module,
        # and per-session by hyprland.lua — makes Qt apps read these. Qt6 apps
        # consult qt6ct/qt6ct.conf with the same format.
        "qt5ct/qt5ct.conf".text = qtCtConf;
        "qt6ct/qt6ct.conf".text = qtCtConf;
      };

      # kdeglobals must be a real file, not a store symlink: Flatpak sandboxes
      # cannot follow a /nix/store path out of the app's filesystem namespace,
      # so a symlinked kdeglobals leaves every Qt flatpak unthemed.
      stubbe.mutable.".config/kdeglobals" = {
        method = "copy";
        source =
          let
            # Breeze Dark accents shared by every Colors:* section.
            breezeColors = {
              DecorationFocus = "61,174,233";
              DecorationHover = "61,174,233";
              ForegroundActive = "61,174,233";
              ForegroundInactive = "161,169,177";
              ForegroundLink = "29,153,243";
              ForegroundNegative = "218,68,83";
              ForegroundNeutral = "246,116,0";
              ForegroundNormal = "252,252,252";
              ForegroundPositive = "39,174,96";
              ForegroundVisited = "155,89,182";
            };
          in
          (pkgs.formats.ini { }).generate "kdeglobals" {
            General = {
              ColorScheme = "BreezeDark";
              Name = "Breeze Dark";
            };

            "ColorEffects:Disabled" = {
              Color = "56,56,56";
              ColorAmount = 0;
              ColorEffect = 0;
              ContrastAmount = 0.65;
              ContrastEffect = 1;
              IntensityAmount = 0.1;
              IntensityEffect = 2;
            };

            "ColorEffects:Inactive" = {
              ChangeSelectionColor = true;
              Color = "112,111,110";
              ColorAmount = 0.025;
              ColorEffect = 2;
              ContrastAmount = 0.1;
              ContrastEffect = 2;
              Enable = false;
              IntensityAmount = 0;
              IntensityEffect = 0;
            };

            "Colors:Button" = breezeColors // {
              BackgroundAlternate = "30,87,116";
              BackgroundNormal = "49,54,59";
            };

            "Colors:Selection" = breezeColors // {
              BackgroundAlternate = "30,87,116";
              BackgroundNormal = "61,174,233";
              ForegroundActive = "252,252,252";
              ForegroundLink = "253,188,75";
              ForegroundNegative = "176,55,69";
              ForegroundNeutral = "198,92,0";
              ForegroundPositive = "23,104,57";
            };

            "Colors:Tooltip" = breezeColors // {
              BackgroundAlternate = "49,54,59";
              BackgroundNormal = "49,54,59";
            };

            "Colors:View" = breezeColors // {
              BackgroundAlternate = "35,38,41";
              BackgroundNormal = "27,30,32";
            };

            "Colors:Window" = breezeColors // {
              BackgroundAlternate = "49,54,59";
              BackgroundNormal = "42,46,50";
            };

            Icons.Theme = "breeze-dark";

            KDE = {
              ColorScheme = "BreezeDark";
              LookAndFeelPackage = "org.kde.breezedark.desktop";
              widgetStyle = "Breeze";
            };

            WM = {
              activeBackground = "49,54,59";
              activeBlend = "252,252,252";
              activeForeground = "252,252,252";
              inactiveBackground = "42,46,50";
              inactiveBlend = "161,169,177";
              inactiveForeground = "161,169,177";
            };
          };
      };

      # Snap apps can only see themes installed under /var/lib/snapd/desktop.
      stubbe.setup.snapThemes = {
        privileged = true;
        title = "Installing Vimix icon/cursor themes for snaps";
        body = ''
          Snap apps can only see themes installed under /var/lib/snapd/desktop.
          This will install the Vimix icon and cursor themes for snaps.
        '';
        preCheck = pkgs.stubbe.requirePath "/var/lib/snapd/desktop";
        script = ''
          ICON_DIR="/var/lib/snapd/desktop/icons"
          sudo mkdir -p "$ICON_DIR"
          sudo cp -a "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark" "$ICON_DIR/"
          sudo cp -a "${pkgs.vimix-cursors}/share/icons/${theme.cursor}" "$ICON_DIR/"
        '';
      };
    };
}
