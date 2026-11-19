_: {
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      c = pkgs.stubbe.withHash;

      unit = "app-com.mitchellh.ghostty.service";

      ghosttyClient = pkgs.stubbe.shellScriptBin "ghostty" ''
        real="${lib.getExe pkgs.ghostty}"

        case "''${1:-}" in
          +* | --class=* | --help | -h | --version | -V)
            exec "$real" "$@"
            ;;
        esac

        exec "$real" +new-window "$@"
      '';

      ghostty = pkgs.symlinkJoin {
        name = "ghostty-${pkgs.ghostty.version}";
        paths = [
          ghosttyClient
          pkgs.ghostty
        ];
        meta = pkgs.ghostty.meta // {
          mainProgram = "ghostty";
          outputsToInstall = [ "out" ];
        };
      };

      palette = [
        c.surface1
        c.red
        c.green
        c.yellow
        c.blue
        c.pink
        c.teal
        c.subtext1
        c.surface2
        c.red
        c.green
        c.yellow
        c.blue
        c.pink
        c.teal
        c.subtext0
        c.peach
        c.rosewater
      ];
    in
    lib.mkIf config.features.desktop {
      programs.ghostty = {
        enable = true;
        package = ghostty;
        settings = {
          font-family = "JetBrainsMono Nerd Font";
          font-size = 12;
          adjust-icon-height = "25%";

          window-padding-x = 0;
          window-padding-y = 0;
          window-padding-balance = true;
          window-decoration = "server";
          resize-overlay = "never";
          confirm-close-surface = false;
          quit-after-last-window-closed = false;

          scrollback-limit-bytes = 0;
          mouse-hide-while-typing = true;
          cursor-style = "block";
          cursor-style-blink = false;
          shell-integration-features = "no-cursor";

          background = c.base;
          foreground = c.text;
          cursor-color = c.rosewater;
          cursor-text = c.base;
          selection-background = c.rosewater;
          selection-foreground = c.base;
          search-background = c.subtext0;
          search-foreground = c.base;
          search-selected-background = c.green;
          search-selected-foreground = c.base;
          palette = lib.imap0 (index: color: "${toString index}=${color}") palette;

          keybind = [
            "clear"
            "ctrl+shift+c=copy_to_clipboard"
            "ctrl+shift+v=paste_from_clipboard"
            "ctrl+equal=increase_font_size:1"
            "ctrl+plus=increase_font_size:1"
            "ctrl+minus=decrease_font_size:1"
            "ctrl+zero=reset_font_size"
            "ctrl+space=csi:32;5u"
            "ctrl+shift+space=csi:32;6u"
            "shift+enter=csi:13;2u"
          ];
        };
      };

      xdg.configFile."systemd/user/${config.wayland.systemd.target}.wants/${unit}" =
        lib.mkIf config.features.lysWm
          {
            source = config.xdg.configFile."systemd/user/${unit}".source;
          };
    };
}
