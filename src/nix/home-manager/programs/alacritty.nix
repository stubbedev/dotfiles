{ config, pkgs, ... }:
{
  programs.alacritty = {
    enable = true;
    settings = {
      bell = {
        animation = "EaseOutExpo";
        duration = 0;
      };

      colors = {
        indexed_colors = [
          { color = "#fab387"; index = 16; }
          { color = "#f5e0dc"; index = 17; }
        ];
        bright = {
          black = "#585b70";
          blue = "#89b4fa";
          cyan = "#94e2d5";
          green = "#a6e3a1";
          magenta = "#f5c2e7";
          red = "#f38ba8";
          white = "#a6adc8";
          yellow = "#f9e2af";
        };
        cursor = {
          cursor = "#f5e0dc";
          text = "#1e1e2e";
        };
        footer_bar = {
          background = "#a6adc8";
          foreground = "#1e1e2e";
        };
        hints = {
          end = {
            background = "#a6adc8";
            foreground = "#1e1e2e";
          };
          start = {
            background = "#f9e2af";
            foreground = "#1e1e2e";
          };
        };
        normal = {
          black = "#45475a";
          blue = "#89b4fa";
          cyan = "#94e2d5";
          green = "#a6e3a1";
          magenta = "#f5c2e7";
          red = "#f38ba8";
          white = "#bac2de";
          yellow = "#f9e2af";
        };
        primary = {
          background = "#1e1e2e";
          bright_foreground = "#cdd6f4";
          dim_foreground = "#7f849c";
          foreground = "#cdd6f4";
        };
        search = {
          focused_match = {
            background = "#a6e3a1";
            foreground = "#1e1e2e";
          };
          matches = {
            background = "#a6adc8";
            foreground = "#1e1e2e";
          };
        };
        selection = {
          background = "#f5e0dc";
          text = "#1e1e2e";
        };
        vi_mode_cursor = {
          cursor = "#b4befe";
          text = "#1e1e2e";
        };
      };

      cursor = {
        style = "Block";
        unfocused_hollow = true;
      };

      font = {
        size = 12;
        bold = {
          family = "JetBrains Mono Nerd Font";
          style = "Bold";
        };
        glyph_offset = {
          x = 0;
          y = 0;
        };
        italic = {
          family = "JetBrains Mono Nerd Font";
          style = "Italic";
        };
        normal = {
          family = "JetBrains Mono Nerd Font";
          style = "Regular";
        };
        offset = {
          x = 0;
          y = 0;
        };
      };

      live_config_reload = true;

      keyboard = {
        bindings = [
          { action = "ReceiveChar"; key = "PageUp"; mode = "~Alt"; mods = "Shift"; }
          { action = "ReceiveChar"; key = "PageDown"; mode = "~Alt"; mods = "Shift"; }
          { action = "ReceiveChar"; key = "Home"; mode = "~Alt"; mods = "Shift"; }
          { action = "ReceiveChar"; key = "End"; mode = "~Alt"; mods = "Shift"; }
          { action = "ReceiveChar"; key = "K"; mode = "~Vi|~Search"; mods = "Command"; }
          { action = "ReceiveChar"; key = "F"; mode = "~Search"; mods = "Control|Shift"; }
          { action = "ReceiveChar"; key = "F"; mode = "~Search"; mods = "Command"; }
          { action = "ReceiveChar"; key = "B"; mode = "~Search"; mods = "Control|Shift"; }
          { action = "ReceiveChar"; key = "B"; mode = "~Search"; mods = "Command"; }
          { action = "ReceiveChar"; key = "Paste"; }
          { action = "ReceiveChar"; key = "Copy"; }
          { action = "ReceiveChar"; key = "V"; mods = "Command"; }
          { action = "ReceiveChar"; key = "C"; mods = "Command"; }
          { action = "ReceiveChar"; key = "C"; mode = "Vi|~Search"; mods = "Command"; }
          { action = "ReceiveChar"; key = "Insert"; mods = "Shift"; }
        ];
      };

      mouse = {
        hide_when_typing = true;
        bindings = [
          { action = "PasteSelection"; mouse = "Middle"; }
        ];
      };

      scrolling = {
        history = 0;
      };

      selection = {
        save_to_clipboard = false;
      };

      window = {
        decorations = "none";
        dynamic_padding = true;
        dynamic_title = true;
        startup_mode = "Maximized";
        dimensions = {
          columns = 0;
          lines = 0;
        };
        padding = {
          x = 0;
          y = 0;
        };
      };
    };
  };
}
