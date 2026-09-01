_: {
  flake.modules.homeManager.rofi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # rasi values that are neither a quoted string, a number, nor a @reference:
      # dimensions ("10 14"), keywords (transparent, inherit), em sizes.
      lit = pkgs.stubbe.rasiLiteral;
    in
    lib.mkIf config.features.hyprland {
      home.packages = [ (config.stubbe.gfx.wrap pkgs.rofi) ];

      xdg.configFile = lib.mkMerge [
        (pkgs.stubbe.conf.rasi {
          "rofi/config.rasi" = {
            imports = [ "catppuccin-mocha" ];
            theme = "catppuccin-default";
            sections.configuration = {
              matching = "fuzzy";
              sort = true;
              sorting-method = "fzf";
              drun-match-fields = "name,generic,keywords";
              drun-show-actions = true;
              show-icons = true;
              icon-theme = pkgs.stubbe.theme.icon;
              lines = 10;
            };
          };

          # The palette itself: every catppuccin colour as a rasi variable the
          # theme below refers to by @name.
          "rofi/catppuccin-mocha.rasi".sections."*" = pkgs.stubbe.withHash;

          "rofi/catppuccin-default.rasi" = {
            imports = [ "catppuccin-mocha" ];
            sections = {
              "*" = {
                selected-active-foreground = "@background";
                lightfg = "@text";
                separatorcolor = "@surface0";
                urgent-foreground = "@red";
                alternate-urgent-background = "@mantle";
                lightbg = "@mantle";
                background-color = lit "transparent";
                border-color = "@mauve";
                normal-background = "@base";
                selected-urgent-background = "@red";
                alternate-active-background = "@mantle";
                spacing = 4;
                alternate-normal-foreground = "@subtext1";
                urgent-background = "@base";
                selected-normal-foreground = "@text";
                active-foreground = "@mauve";
                background = "@base";
                selected-active-background = "@mauve";
                active-background = "@base";
                selected-normal-background = "@surface0";
                alternate-normal-background = "@base";
                foreground = "@text";
                selected-urgent-foreground = "@background";
                normal-foreground = "@subtext1";
                alternate-urgent-foreground = "@red";
                alternate-active-foreground = "@mauve";
                border-radius = 0;
              };

              window = {
                padding = 12;
                background-color = "@mantle";
                border = 1;
                border-color = "@mauve";
                location = lit "north";
                anchor = lit "north";
                y-offset = lit "33%";
              };

              mainbox = {
                padding = 0;
                border = 0;
                spacing = 8;
              };

              inputbar = {
                padding = lit "10 14";
                spacing = 10;
                text-color = "@text";
                background-color = "@base";
                children = [
                  "prompt"
                  "textbox-prompt-colon"
                  "entry"
                ];
              };

              prompt = {
                spacing = 0;
                text-color = "@mauve";
              };

              textbox-prompt-colon = {
                margin = 0;
                expand = false;
                str = "";
              };

              entry = {
                text-color = "@text";
                cursor = lit "text";
                spacing = 0;
                placeholder-color = "@overlay0";
                placeholder = "Search apps...";
              };

              case-indicator = {
                spacing = 0;
                text-color = "@overlay0";
              };

              message = {
                padding = lit "8 14";
                border = 0;
                background-color = "@base";
              };

              textbox.text-color = "@subtext1";

              listview = {
                padding = lit "4 0";
                scrollbar = false;
                border = 0;
                spacing = 2;
                fixed-height = false;
                lines = 10;
              };

              element = {
                padding = lit "8 12";
                cursor = lit "pointer";
                spacing = 10;
                border = 0;
              };

              "element normal.normal" = {
                background-color = "@normal-background";
                text-color = "@normal-foreground";
              };

              "element normal.urgent" = {
                background-color = "@urgent-background";
                text-color = "@urgent-foreground";
              };

              "element normal.active" = {
                background-color = "@active-background";
                text-color = "@active-foreground";
              };

              "element selected.normal" = {
                background-color = "@selected-normal-background";
                text-color = "@selected-normal-foreground";
              };

              "element selected.urgent" = {
                background-color = "@selected-urgent-background";
                text-color = "@selected-urgent-foreground";
              };

              "element selected.active" = {
                background-color = "@selected-active-background";
                text-color = "@selected-active-foreground";
              };

              "element alternate.normal" = {
                background-color = "@normal-background";
                text-color = "@normal-foreground";
              };

              "element alternate.urgent" = {
                background-color = "@alternate-urgent-background";
                text-color = "@alternate-urgent-foreground";
              };

              "element alternate.active" = {
                background-color = "@alternate-active-background";
                text-color = "@alternate-active-foreground";
              };

              element-text = {
                background-color = lit "transparent";
                cursor = lit "inherit";
                highlight = "@mauve";
                highlight-color = "@crust";
                text-color = lit "inherit";
              };

              element-icon = {
                background-color = lit "transparent";
                size = lit "1.2em";
                cursor = lit "inherit";
                text-color = lit "inherit";
              };

              scrollbar = {
                width = 0;
                padding = 0;
                handle-width = 0;
                border = 0;
              };

              sidebar.border = 0;

              button = {
                cursor = lit "pointer";
                spacing = 8;
                text-color = "@subtext1";
                padding = lit "6 10";
              };

              "button selected" = {
                background-color = "@surface0";
                text-color = "@text";
              };

              num-filtered-rows = {
                expand = false;
                text-color = "@overlay0";
              };

              num-rows = {
                expand = false;
                text-color = "@overlay0";
              };

              textbox-num-sep = {
                expand = false;
                str = "/";
                text-color = "@overlay0";
              };
            };
          };
        })
        # The palette file is regenerated on every theme switch, so it must win
        # over whatever the previous generation left behind.
        { "rofi/catppuccin-mocha.rasi".force = true; }
      ];
    };
}
