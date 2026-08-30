_: {
  flake.modules.nixos.theming =
    { pkgs, ... }:
    {
      # The HM dconf module writes dconf keys (color-scheme, blueman). On NixOS
      # the dconf service must be enabled system-wide for those to apply —
      # otherwise activation errors with "dconf is not enabled".
      programs.dconf.enable = true;

      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };

      environment.sessionVariables = {
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_USE_XINPUT2 = "1";

        XCURSOR_THEME = pkgs.stubbe.theme.cursor;
        XCURSOR_SIZE = toString pkgs.stubbe.theme.cursorSize;
      };

      fonts = {
        packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          font-awesome
          adwaita-fonts
        ];
        fontconfig.enable = true;
      };

      environment.systemPackages = with pkgs; [
        catppuccin-kvantum
        # Cursor theme system-wide (not just home-manager) so it lands in
        # /run/current-system/sw/share/icons — where the greetd greeter, running
        # as the unprivileged `greeter` user that cannot read a 0700 $HOME, can
        # actually find it. Without it the login screen falls back to the huge
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
      ini = pkgs.formats.ini { };

      qtCtConf = ini.generate "qtct.conf" {
        Appearance = {
          color_scheme_path = "";
          custom_palette = false;
          icon_theme = theme.icon;
          standard_dialogs = "default";
          style = "kvantum";
        };
        Interface = {
          activate_item_on_single_click = 1;
          buttonbox_layout = 0;
          cursor_flash_time = 1000;
          dialog_buttons_have_icons = 1;
          double_click_interval = 400;
          gui_effects = "@Invalid()";
          keyboard_scheme = 2;
          menus_have_icons = true;
          show_shortcuts_in_context_menus = true;
          stylesheets = "@Invalid()";
          toolbutton_style = 4;
          underline_shortcut = 1;
          wheel_scroll_lines = 3;
        };
      };
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

          libsForQt5.qt5ct
          kdePackages.qt6ct
          libsForQt5.qtstyleplugin-kvantum
          kdePackages.qtstyleplugin-kvantum
        ];

        file = {
          ".icons/${theme.cursor}".source = "${pkgs.vimix-cursors}/share/icons/${theme.cursor}";
          ".local/share/icons/${theme.cursor}".source = "${pkgs.vimix-cursors}/share/icons/${theme.cursor}";
          ".local/share/icons/Vimix-dark".source = "${pkgs.vimix-icon-theme}/share/icons/Vimix-dark";

          ".local/share/flatpak/overrides/global".source = ini.generate "flatpak-global" {
            Context.filesystems = "xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;~/.themes:ro;~/.icons:ro;/nix/store:ro";
            Environment = {
              GTK_THEME = "Adwaita-dark";
              QT_QPA_PLATFORMTHEME = "kde";
              QT_STYLE = "breeze";
              COLOR_SCHEME = "prefer-dark";
              GDK_BACKEND = "wayland,x11";
            };
          };
          ".local/share/flatpak/overrides/com.valvesoftware.Steam" = {
            source = ini.generate "flatpak-steam" {
              Context.filesystems = "/run/user/1000";
            };
            force = true;
          };
        };
      };

      xdg.configFile = {
        "Kvantum/kvantum.kvconfig".source = ini.generate "kvantum.kvconfig" {
          General.theme = theme.kvantum;
        };

        "qt5ct/qt5ct.conf".source = qtCtConf;
        "qt6ct/qt6ct.conf".source = qtCtConf;
      };

      # kdeglobals must be a real file, not a store symlink: Flatpak sandboxes
      # cannot follow a /nix/store path out of the app's filesystem namespace,
      # so a symlinked kdeglobals leaves every Qt flatpak unthemed.
      stubbe.mutable.".config/kdeglobals" = {
        method = "copy";
        source =
          let
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
          ini.generate "kdeglobals" {
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
