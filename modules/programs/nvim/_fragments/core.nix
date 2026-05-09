{ ... }:
{
  colorschemes.catppuccin = {
    enable = true;
    settings = {
      flavour = "mocha";
      transparent_background = false;
      integrations = {
        noice = true;
        notify = true;
        cmp = true;
        gitsigns = true;
        treesitter = true;
        treesitter_context = true;
        which_key = true;
        mini = {
          enabled = true;
          indentscope_color = "";
        };
        native_lsp = {
          enabled = true;
          virtual_text = {
            errors = [ "italic" ];
            hints = [ "italic" ];
            warnings = [ "italic" ];
            information = [ "italic" ];
          };
          underlines = {
            errors = [ "underline" ];
            hints = [ "underline" ];
            warnings = [ "underline" ];
            information = [ "underline" ];
          };
        };
        snacks = {
          enabled = true;
          indent_scope_color = "";
        };
        markdown = true;
        mason = false;
        neotest = true;
        nvim_surround = false;
        render_markdown = true;
        telescope.enabled = false;
        dap = true;
        dap_ui = true;
        illuminate = {
          enabled = true;
          lsp = false;
        };
      };
    };
  };

  globals = {
    mapleader = " ";
    maplocalleader = " ";
    autoformat = false;
    lazyvim_php_lsp = "intelephense";
    root_spec = [
      ".git"
      "lsp"
      "cwd"
    ];
  };

  opts = {
    mouse = "";
    foldlevel = 99;
    foldtext = "v:lua.vim.treesitter.foldtext()";
  };

  keymaps = [
    {
      mode = "n";
      key = "<S-h>";
      action = "<cmd>bprevious<cr>";
      options.desc = "Prev Buffer";
    }
    {
      mode = "n";
      key = "<S-l>";
      action = "<cmd>bnext<cr>";
      options.desc = "Next Buffer";
    }
    {
      mode = "n";
      key = "[b";
      action = "<cmd>bprevious<cr>";
      options.desc = "Prev Buffer";
    }
    {
      mode = "n";
      key = "]b";
      action = "<cmd>bnext<cr>";
      options.desc = "Next Buffer";
    }
    {
      mode = "n";
      key = "<leader>bA";
      action.__raw = ''
        function()
          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
              vim.api.nvim_buf_delete(bufnr, { force = true })
            end
          end
        end
      '';
      options.desc = "Delete All Buffers";
    }
    {
      mode = "n";
      key = "<leader>ba";
      action.__raw = ''
        function()
          local current = vim.api.nvim_get_current_buf()
          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if bufnr ~= current and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
              vim.api.nvim_buf_delete(bufnr, { force = true })
            end
          end
        end
      '';
      options.desc = "Delete Other Buffers Except Current";
    }
    {
      mode = "n";
      key = "<leader>ur";
      action = "<cmd>nohlsearch<cr>";
      options.desc = "Clear search highlighting";
    }
    {
      mode = "n";
      key = "gx";
      action.__raw = ''function() vim.ui.open(vim.fn.expand("<cfile>")) end'';
      options.desc = "Open with system app";
    }
    {
      mode = "n";
      key = "<leader>E";
      action = "<cmd>Oil<cr>";
      options.desc = "Oil Editor";
    }
    {
      mode = "n";
      key = "-";
      action = "<cmd>Oil<cr>";
      options.desc = "Oil Editor";
    }
  ];

  autoCmd = [
    {
      event = [
        "BufRead"
        "BufNewFile"
      ];
      pattern = [
        ".env"
        ".env.*"
        "*.env"
      ];
      callback.__raw = ''
        function(args)
          vim.diagnostic.enable(false, { bufnr = args.buf })
        end
      '';
    }
    {
      event = [ "LspAttach" ];
      callback.__raw = ''
        function(args)
          vim.lsp.inlay_hint.enable(false, { bufnr = args.buf })
        end
      '';
    }
  ];

  extraConfigLua = ''
    vim.treesitter.language.register("html", { "html", "tmpl" })
    vim.treesitter.language.register("templ", { "templ", "tmpl" })

    vim.filetype.add({
      extension = { caddy = "caddy" },
      filename = { Caddyfile = "caddy" },
    })

    vim.lsp.handlers["textDocument/hover"] = function(_, result, ctx, config)
      config = config or {}
      config.focus_id = ctx.method
      if not (result and result.contents) then
        return
      end
      local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
      local markdown_lines_string = table.concat(markdown_lines, "\n")
      markdown_lines = vim.split(markdown_lines_string, "\r\n|\r|\n", { trimempty = true })
      if vim.tbl_isempty(markdown_lines) then
        return
      end
      return vim.lsp.util.open_floating_preview(markdown_lines, "markdown", config)
    end
  '';
}
