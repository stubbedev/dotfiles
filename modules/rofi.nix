_: {
  flake.modules.homeManager.rofi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.lib.formats.rasi) mkLiteral;
    in
    lib.mkIf config.features.hyprland {
      programs.rofi = {
        enable = true;
        package = config.stubbe.gfx.wrap pkgs.rofi;

        settings = {
          matching = "fuzzy";
          sort = true;
          sorting-method = "fzf";
          drun-match-fields = "name,generic,keywords";
          drun-show-actions = true;
          show-icons = true;
          icon-theme = pkgs.stubbe.theme.icon;
          lines = 10;
        };

        theme = {
          # The palette: every catppuccin colour as a rasi variable the
          # sections below refer to by @name.
          "*" = (builtins.mapAttrs (_: mkLiteral) pkgs.stubbe.withHash) // {
            selected-active-foreground = mkLiteral "@background";
            lightfg = mkLiteral "@text";
            separatorcolor = mkLiteral "@surface0";
            urgent-foreground = mkLiteral "@red";
            alternate-urgent-background = mkLiteral "@mantle";
            lightbg = mkLiteral "@mantle";
            background-color = mkLiteral "transparent";
            border-color = mkLiteral "@mauve";
            normal-background = mkLiteral "@base";
            selected-urgent-background = mkLiteral "@red";
            alternate-active-background = mkLiteral "@mantle";
            spacing = 4;
            alternate-normal-foreground = mkLiteral "@subtext1";
            urgent-background = mkLiteral "@base";
            selected-normal-foreground = mkLiteral "@text";
            active-foreground = mkLiteral "@mauve";
            background = mkLiteral "@base";
            selected-active-background = mkLiteral "@mauve";
            active-background = mkLiteral "@base";
            selected-normal-background = mkLiteral "@surface0";
            alternate-normal-background = mkLiteral "@base";
            foreground = mkLiteral "@text";
            selected-urgent-foreground = mkLiteral "@background";
            normal-foreground = mkLiteral "@subtext1";
            alternate-urgent-foreground = mkLiteral "@red";
            alternate-active-foreground = mkLiteral "@mauve";
            border-radius = 0;
          };

          window = {
            padding = 12;
            background-color = mkLiteral "@mantle";
            border = 1;
            border-color = mkLiteral "@mauve";
            location = mkLiteral "north";
            anchor = mkLiteral "north";
            y-offset = mkLiteral "33%";
          };

          mainbox = {
            padding = 0;
            border = 0;
            spacing = 8;
          };

          inputbar = {
            padding = mkLiteral "10 14";
            spacing = 10;
            text-color = mkLiteral "@text";
            background-color = mkLiteral "@base";
            children = [
              "prompt"
              "textbox-prompt-colon"
              "entry"
            ];
          };

          prompt = {
            spacing = 0;
            text-color = mkLiteral "@mauve";
          };

          textbox-prompt-colon = {
            margin = 0;
            expand = false;
            str = "";
          };

          entry = {
            text-color = mkLiteral "@text";
            cursor = mkLiteral "text";
            spacing = 0;
            placeholder-color = mkLiteral "@overlay0";
            placeholder = "Search apps...";
          };

          case-indicator = {
            spacing = 0;
            text-color = mkLiteral "@overlay0";
          };

          message = {
            padding = mkLiteral "8 14";
            border = 0;
            background-color = mkLiteral "@base";
          };

          textbox.text-color = mkLiteral "@subtext1";

          listview = {
            padding = mkLiteral "4 0";
            scrollbar = false;
            border = 0;
            spacing = 2;
            fixed-height = false;
            lines = 10;
          };

          element = {
            padding = mkLiteral "8 12";
            cursor = mkLiteral "pointer";
            spacing = 10;
            border = 0;
          };

          "element normal.normal" = {
            background-color = mkLiteral "@normal-background";
            text-color = mkLiteral "@normal-foreground";
          };

          "element normal.urgent" = {
            background-color = mkLiteral "@urgent-background";
            text-color = mkLiteral "@urgent-foreground";
          };

          "element normal.active" = {
            background-color = mkLiteral "@active-background";
            text-color = mkLiteral "@active-foreground";
          };

          "element selected.normal" = {
            background-color = mkLiteral "@selected-normal-background";
            text-color = mkLiteral "@selected-normal-foreground";
          };

          "element selected.urgent" = {
            background-color = mkLiteral "@selected-urgent-background";
            text-color = mkLiteral "@selected-urgent-foreground";
          };

          "element selected.active" = {
            background-color = mkLiteral "@selected-active-background";
            text-color = mkLiteral "@selected-active-foreground";
          };

          "element alternate.normal" = {
            background-color = mkLiteral "@normal-background";
            text-color = mkLiteral "@normal-foreground";
          };

          "element alternate.urgent" = {
            background-color = mkLiteral "@alternate-urgent-background";
            text-color = mkLiteral "@alternate-urgent-foreground";
          };

          "element alternate.active" = {
            background-color = mkLiteral "@alternate-active-background";
            text-color = mkLiteral "@alternate-active-foreground";
          };

          element-text = {
            background-color = mkLiteral "transparent";
            cursor = mkLiteral "inherit";
            highlight = mkLiteral "@mauve";
            highlight-color = mkLiteral "@crust";
            text-color = mkLiteral "inherit";
          };

          element-icon = {
            background-color = mkLiteral "transparent";
            size = mkLiteral "1.2em";
            cursor = mkLiteral "inherit";
            text-color = mkLiteral "inherit";
          };

          scrollbar = {
            width = 0;
            padding = 0;
            handle-width = 0;
            border = 0;
          };

          sidebar.border = 0;

          button = {
            cursor = mkLiteral "pointer";
            spacing = 8;
            text-color = mkLiteral "@subtext1";
            padding = mkLiteral "6 10";
          };

          "button selected" = {
            background-color = mkLiteral "@surface0";
            text-color = mkLiteral "@text";
          };

          num-filtered-rows = {
            expand = false;
            text-color = mkLiteral "@overlay0";
          };

          num-rows = {
            expand = false;
            text-color = mkLiteral "@overlay0";
          };

          textbox-num-sep = {
            expand = false;
            str = "/";
            text-color = mkLiteral "@overlay0";
          };
        };
      };
    };
}
