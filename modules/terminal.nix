_: {
  flake.modules.homeManager.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      c = pkgs.stubbe.withHash;

      # Nix string literals have no \u escape; a JSON one does.
      esc = builtins.fromJSON ''"\u001b"'';

      alacrittyGfx = gfx.wrap pkgs.alacritty;

      alacrittyClient = pkgs.stubbe.shellScriptBin "alacritty" ''
        real="${alacrittyGfx}/bin/alacritty"
        socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/alacritty.sock"

        case "''${1:-}" in
          --daemon|msg|--help|-h|--version|-V)
            exec "$real" "$@"
            ;;
        esac

        if "$real" msg --socket "$socket" create-window "$@" >/dev/null 2>&1; then
          exit 0
        fi
        exec "$real" "$@"
      '';

      # Client first so it shadows upstream bin/alacritty. writeShellScriptBin
      # emits only bin/, so without the join there is no .desktop entry and
      # alacritty never shows in rofi.
      alacritty = pkgs.symlinkJoin {
        name = "alacritty-${pkgs.alacritty.version}";
        paths = [
          alacrittyClient
          pkgs.alacritty
        ];
        meta = pkgs.alacritty.meta // {
          mainProgram = "alacritty";
          # symlinkJoin yields a single `out` (terminfo merged in); inheriting
          # alacritty's multi-output outputsToInstall would make buildEnv fail
          # on the missing output.
          outputsToInstall = [ "out" ];
        };
      };
    in
    lib.mkIf config.features.desktop {
      # A stale pre-home-manager real file may sit at this path; without force
      # activation aborts with "would be clobbered". HM owns the content.
      xdg.configFile."alacritty/alacritty.toml".force = true;

      programs.alacritty = {
        enable = true;
        package = alacritty;
        settings = {
          general.live_config_reload = true;

          window = {
            dynamic_title = true;
            dynamic_padding = true;
            dimensions = {
              columns = 0;
              lines = 0;
            };
            padding = {
              x = 0;
              y = 0;
            };
          };

          scrolling.history = 0;

          font = {
            size = 12;
            normal = {
              family = "JetBrainsMono Nerd Font";
              style = "Regular";
            };
            bold = {
              family = "JetBrainsMono Nerd Font";
              style = "Bold";
            };
            italic = {
              family = "JetBrainsMono Nerd Font";
              style = "Italic";
            };
            offset = {
              x = 0;
              y = 0;
            };
            glyph_offset = {
              x = 0;
              y = 0;
            };
          };

          bell = {
            animation = "EaseOutExpo";
            duration = 0;
          };

          mouse = {
            hide_when_typing = true;
            bindings = [
              {
                mouse = "Middle";
                action = "PasteSelection";
              }
            ];
          };

          cursor = {
            style = "Block";
            unfocused_hollow = true;
          };

          selection.save_to_clipboard = false;

          # ReceiveChar hands the key straight to the application instead of
          # letting alacritty act on it, so tmux/neovim see the real sequence.
          # The two Control+Space entries emit CSI-u so tmux can tell
          # Ctrl+Space from Ctrl+Shift+Space.
          keyboard.bindings =
            let
              receiveChar = spec: spec // { action = "ReceiveChar"; };
            in
            [
              (receiveChar {
                key = "PageUp";
                mods = "Shift";
                mode = "~Alt";
              })
              (receiveChar {
                key = "PageDown";
                mods = "Shift";
                mode = "~Alt";
              })
              (receiveChar {
                key = "Home";
                mods = "Shift";
                mode = "~Alt";
              })
              (receiveChar {
                key = "End";
                mods = "Shift";
                mode = "~Alt";
              })
              (receiveChar {
                key = "K";
                mods = "Command";
                mode = "~Vi|~Search";
              })
              (receiveChar {
                key = "F";
                mods = "Control|Shift";
                mode = "~Search";
              })
              (receiveChar {
                key = "F";
                mods = "Command";
                mode = "~Search";
              })
              (receiveChar {
                key = "B";
                mods = "Control|Shift";
                mode = "~Search";
              })
              (receiveChar {
                key = "B";
                mods = "Command";
                mode = "~Search";
              })
              {
                key = "Space";
                mods = "Control";
                mode = "~Search";
                chars = "${esc}[32;5u";
              }
              {
                key = "Space";
                mods = "Control|Shift";
                mode = "~Search";
                chars = "${esc}[32;6u";
              }
              (receiveChar { key = "Paste"; })
              (receiveChar { key = "Copy"; })
              (receiveChar {
                key = "V";
                mods = "Command";
              })
              (receiveChar {
                key = "C";
                mods = "Command";
              })
              (receiveChar {
                key = "C";
                mods = "Command";
                mode = "Vi|~Search";
              })
              (receiveChar {
                key = "Insert";
                mods = "Shift";
              })
              {
                key = "Return";
                mods = "Shift";
                chars = "${esc}[13;2u";
              }
            ];

          colors = {
            primary = {
              background = c.base;
              foreground = c.text;
              dim_foreground = c.overlay1;
              bright_foreground = c.text;
            };
            cursor = {
              text = c.base;
              cursor = c.rosewater;
            };
            vi_mode_cursor = {
              text = c.base;
              cursor = c.lavender;
            };
            search = {
              matches = {
                foreground = c.base;
                background = c.subtext0;
              };
              focused_match = {
                foreground = c.base;
                background = c.green;
              };
            };
            footer_bar = {
              foreground = c.base;
              background = c.subtext0;
            };
            hints = {
              start = {
                foreground = c.base;
                background = c.yellow;
              };
              end = {
                foreground = c.base;
                background = c.subtext0;
              };
            };
            selection = {
              text = c.base;
              background = c.rosewater;
            };
            normal = {
              black = c.surface1;
              inherit (c) red;
              inherit (c) green;
              inherit (c) yellow;
              inherit (c) blue;
              magenta = c.pink;
              cyan = c.teal;
              white = c.subtext1;
            };
            bright = {
              black = c.surface2;
              inherit (c) red;
              inherit (c) green;
              inherit (c) yellow;
              inherit (c) blue;
              magenta = c.pink;
              cyan = c.teal;
              white = c.subtext0;
            };
            indexed_colors = [
              {
                index = 16;
                color = c.peach;
              }
              {
                index = 17;
                color = c.rosewater;
              }
            ];
          };
        };
      };

      systemd.user.services.alacritty-daemon = lib.mkIf config.features.hyprland {
        Unit = {
          Description = "Alacritty daemon (shared single-instance process)";
          After = [ "hyprland-session.target" ];
          PartOf = [ "hyprland-session.target" ];
          # Never restart on `hm switch`. KillMode=control-group plus
          # single-instance means a restart takes every terminal window with it
          # — and every tmux server, which double-forks but stays in this unit's
          # cgroup. Any alacritty store-path bump changes the unit file, so
          # sd-switch would otherwise restart it on a routine flake update. A new
          # binary lands on next login, or on an explicit restart.
          X-SwitchMethod = "keep-old";
        };
        Install.WantedBy = [ "hyprland-session.target" ];
        Service = {
          Type = "simple";
          ExecStart = "${alacrittyGfx}/bin/alacritty --socket %t/alacritty.sock --daemon";
          Restart = "on-failure";
          RestartSec = "2s";
        };
      };
    };
}
