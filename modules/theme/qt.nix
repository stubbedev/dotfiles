_: {
  flake.modules.homeManager.themeQt =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.theming {
      xdg.configFile = {
        # Kvantum theme selection. The Catppuccin-Mocha-Mauve theme files
        # come from catppuccin-kvantum (system package on NixOS, or user
        # package on non-NixOS via modules/packages/theming.nix once added).
        "Kvantum/kvantum.kvconfig".text = ''
          [General]
          theme=Catppuccin-Mocha-Mauve
        '';

        # qt5ct style: delegate to Kvantum for widget rendering.
        # QT_QPA_PLATFORMTHEME=qt5ct (set by NixOS qt module system-wide, and
        # by compositor env.conf for the session) makes Qt apps read this file.
        # qt6ct reads ~/.config/qt6ct/qt6ct.conf with the same format.
        "qt5ct/qt5ct.conf".text = ''
          [Appearance]
          color_scheme_path=
          custom_palette=false
          icon_theme=Tela-circle-purple-dark
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

        "qt6ct/qt6ct.conf".text = ''
          [Appearance]
          color_scheme_path=
          custom_palette=false
          icon_theme=Tela-circle-purple-dark
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
      };
    };
}
