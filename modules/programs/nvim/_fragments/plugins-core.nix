{ pkgs, ... }:
let
  nvimRecorder = pkgs.vimUtils.buildVimPlugin {
    pname = "nvim-recorder";
    version = "unstable-2026-04-13";
    src = pkgs.fetchFromGitHub {
      owner = "chrisgrieser";
      repo = "nvim-recorder";
      rev = "7acba6f7bbafb242f71c87e3f0ac4b1c40f03a96";
      hash = "sha256-E/QFpMyYi4CJ2YXb4Bm76GLsa59RPQtsJwvHRwVBJP0=";
    };
  };
in
{
  plugins = {
    snacks = {
      enable = true;
      settings = {
        terminal.enabled = false;
        explorer.enabled = false;
        scroll.enabled = false;
        indent = {
          enabled = false;
          scope.enabled = false;
        };
        dashboard = {
          preset = {
            header = "███████╗████████╗██╗   ██╗██████╗ ██████╗ ███████╗\n██╔════╝╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔════╝\n███████╗   ██║   ██║   ██║██████╔╝██████╔╝█████╗  \n╚════██║   ██║   ██║   ██║██╔══██╗██╔══██╗██╔══╝  \n███████║   ██║   ╚██████╔╝██████╔╝██████╔╝███████╗\n╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝";
            keys = [
              { icon = " "; key = "f"; desc = "Find File"; action = ":lua Snacks.dashboard.pick('files')"; }
              { icon = " "; key = "n"; desc = "New File"; action = ":ene | startinsert"; }
              { icon = " "; key = "g"; desc = "Find Text"; action = ":lua Snacks.dashboard.pick('live_grep')"; }
              { icon = " "; key = "r"; desc = "Recent Files"; action = ":lua Snacks.dashboard.pick('oldfiles')"; }
              { icon = " "; key = "c"; desc = "Config"; action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})"; }
              { icon = " "; key = "s"; desc = "Restore Session"; action = ":lua require('persistence').load()"; }
              { icon = " "; key = "q"; desc = "Quit"; action = ":qa"; }
            ];
          };
          sections = [
            { section = "header"; }
            {
              section = "keys";
              gap = 1;
              padding = 1;
            }
            {
              pane = 2;
              icon = " ";
              title = "Recent Files";
              section = "recent_files";
              indent = 2;
              padding = 1;
            }
            {
              pane = 2;
              icon = " ";
              title = "Projects";
              section = "projects";
              indent = 2;
              padding = 1;
            }
          ];
        };
        picker = {
          sources = {
            files = {
              ignored = false;
              hidden = false;
            };
            grep = {
              ignored = false;
              hidden = false;
            };
            git_grep = {
              ignored = false;
              hidden = false;
            };
            explorer = {
              ignored = false;
              hidden = false;
            };
          };
        };
      };
    };

    noice = {
      enable = true;
      settings = {
        lsp = {
          hover.silent = true;
          override = {
            "vim.lsp.util.convert_input_to_markdown_lines" = true;
            "vim.lsp.util.stylize_markdown" = true;
            "cmp.entry.get_documentation" = true;
          };
        };
        routes = [
          {
            filter = {
              event = "msg_show";
              any = [
                { find = "%d+L, %d+B"; }
                { find = "; after #%d+"; }
                { find = "; before #%d+"; }
              ];
            };
            view = "mini";
          }
        ];
        presets = {
          bottom_search = true;
          command_palette = true;
          long_message_to_split = true;
        };
      };
    };

    edgy = {
      enable = true;
      settings.animate.enabled = false;
    };

    which-key = {
      enable = true;
      settings = {
        preset = "classic";
        win.no_overlap = false;
      };
    };

    oil = {
      enable = true;
      settings = {
        default_file_explorer = true;
        columns = [ "icon" ];
        buf_options = {
          buflisted = false;
          bufhidden = "hide";
        };
        win_options = {
          wrap = false;
          signcolumn = "yes:2";
          cursorcolumn = false;
          foldcolumn = "0";
          spell = false;
          list = false;
          conceallevel = 3;
          concealcursor = "nvic";
        };
        delete_to_trash = false;
        skip_confirm_for_simple_edits = false;
        prompt_save_on_select_new_entry = true;
        cleanup_delay_ms = 2000;
        keymaps = {
          "g?" = "actions.show_help";
          "<CR>" = "actions.select";
          "<C-s>" = "actions.select_vsplit";
          "<C-h>" = "actions.select_split";
          "<C-t>" = "actions.select_tab";
          "<C-p>" = "actions.preview";
          "<leader>e" = "actions.close";
          "<C-c>" = "actions.close";
          "<C-l>" = "actions.refresh";
          "-" = "actions.parent";
          "_" = "actions.open_cwd";
          "`" = "actions.cd";
          "~" = "actions.tcd";
          "gs" = "actions.change_sort";
          "gx" = "actions.open_external";
          "g." = "actions.toggle_hidden";
          "g\\" = "actions.toggle_trash";
        };
        use_default_keymaps = true;
        view_options = {
          show_hidden = true;
          is_hidden_file.__raw = ''
            function(name, _bufnr) return vim.startswith(name, ".") end
          '';
          is_always_hidden.__raw = ''
            function(name, bufnr)
              if vim.fn.executable("git") == 0 then return false end
              local oil = require("oil")
              local dir = oil.get_current_dir(bufnr)
              if not dir then return false end
              local path = vim.fs.joinpath(dir, name)
              local result = vim.system({ "git", "-C", dir, "check-ignore", "-q", path }):wait()
              return result.code == 0
            end
          '';
          sort = [
            [
              "type"
              "asc"
            ]
            [
              "name"
              "asc"
            ]
          ];
        };
        float = {
          padding = 2;
          max_width = 0;
          max_height = 0;
          win_options.winblend = 0;
        };
        preview = {
          max_width = 0.9;
          min_width = [
            40
            0.4
          ];
          max_height = 0.9;
          min_height = [
            5
            0.1
          ];
          win_options.winblend = 0;
          update_on_cursor_moved = true;
        };
        progress = {
          max_width = 0.9;
          min_width = [
            40
            0.4
          ];
          max_height = [
            10
            0.9
          ];
          min_height = [
            5
            0.1
          ];
          border = "rounded";
          minimized_border = "none";
          win_options.winblend = 0;
        };
      };
    };

    oil-git-status.enable = true;

    web-devicons.enable = true;

    notify = {
      enable = true;
      settings = {
        render = "compact";
        stages = "static";
        background_colour = "transparent";
      };
    };

    gitsigns.enable = true;
    todo-comments.enable = true;
    trouble.enable = true;
    persistence.enable = true;
    illuminate.enable = true;
    ts-comments.enable = true;
    render-markdown.enable = true;
    markdown-preview.enable = true;

    mini = {
      enable = true;
      modules = {
        ai = { };
        pairs = { };
        surround = { };
        hipatterns = { };
        icons = { };
      };
    };

    lualine.enable = true;
  };

  extraPlugins = [
    nvimRecorder
    pkgs.vimPlugins.nvim-lint
  ];

  extraConfigLuaPost = ''
    -- nvim-recorder setup (must run before lualine integration)
    require("recorder").setup({
      slots = { "a", "b", "c" },
      dynamicSlots = "rotate",
      mapping = {
        startStopRecording = "q",
        playMacro = "Q",
        switchSlot = "<C-q>",
        editMacro = "cq",
        deleteAllMacros = "dq",
        yankMacro = "yq",
        addBreakPoint = "^^",
      },
      clear = false,
      logLevel = vim.log.levels.INFO,
      lessNotifications = true,
      useNerdfontIcons = true,
      performanceOpts = {
        countThreshold = 100,
        lazyredraw = true,
        noSystemClipboard = true,
        autocmdEventsIgnore = {
          "TextChangedI",
          "TextChanged",
          "InsertLeave",
          "InsertEnter",
          "InsertCharPre",
        },
      },
      dapSharedKeymaps = false,
      timeout = 300,
    })

    -- Lualine config: theme + tabline + custom statusline integrations
    do
      local function get_tabline()
        local buffers = vim.tbl_filter(function(bufnr)
          return vim.api.nvim_buf_is_loaded(bufnr) and (vim.fn.buflisted(bufnr) == 1)
        end, vim.api.nvim_list_bufs())
        if #buffers < 2 then return nil end
        return {
          lualine_a = {
            {
              "buffers",
              show_filename_only = true,
              hide_filename_extension = false,
              show_modified_status = true,
              mode = 0,
              max_length = vim.o.columns,
              filetype_names = { snacks_dashboard = "" },
              use_mode_colors = true,
              symbols = { modified = " ●", alternate_file = "^", directory = "" },
            },
          },
        }
      end

      local function update_lualine_tabline()
        local lualine = require("lualine")
        local config = lualine.get_config()
        config.tabline = get_tabline()
        lualine.setup(config)
      end

      vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
        callback = function()
          vim.schedule(function() pcall(update_lualine_tabline) end)
        end,
        nested = true,
      })

      local lualine = require("lualine")
      local current = lualine.get_config()
      local lualineZ = (current.sections and current.sections.lualine_z) or {}
      local lualineY = (current.sections and current.sections.lualine_y) or {}
      local lualineX = (current.sections and current.sections.lualine_x) or {}
      table.insert(lualineZ, { require("recorder").recordingStatus })
      table.insert(lualineY, { require("recorder").displaySlots })
      table.insert(lualineX, 1, {
        "filename",
        file_status = false,
        newfile_status = false,
        path = 1,
        shorting_target = 40,
        symbols = { modified = "", readonly = "", unnamed = "", newfile = "" },
      })

      lualine.setup({
        options = {
          theme = "catppuccin-mocha",
          extensions = { "lazy", "mason", "oil", "nvim-dap", "overseer", "trouble" },
        },
        sections = {
          lualine_c = {},
          lualine_x = lualineX,
          lualine_y = lualineY,
          lualine_z = lualineZ,
        },
        tabline = get_tabline(),
      })
    end
  '';
}
