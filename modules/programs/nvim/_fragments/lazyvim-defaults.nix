{ ... }:
{
  opts = {
    autowrite = true;
    clipboard = "unnamedplus";
    completeopt = "menu,menuone,noselect";
    conceallevel = 2;
    confirm = true;
    cursorline = true;
    expandtab = true;
    fillchars = "fold: ,foldsep: ,diff:╱,eob: ";
    foldmethod = "indent";
    foldtext = "v:lua.vim.treesitter.foldtext()";
    formatoptions = "jcroqlnt";
    grepformat = "%f:%l:%c:%m";
    grepprg = "rg --vimgrep";
    ignorecase = true;
    inccommand = "nosplit";
    jumpoptions = "view";
    laststatus = 3;
    linebreak = true;
    list = true;
    number = true;
    pumblend = 10;
    pumheight = 10;
    relativenumber = true;
    ruler = false;
    scrolloff = 4;
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds";
    shiftround = true;
    shiftwidth = 2;
    showmode = false;
    sidescrolloff = 8;
    signcolumn = "yes";
    smartcase = true;
    smartindent = true;
    smoothscroll = true;
    spelllang = [ "en" ];
    splitbelow = true;
    splitkeep = "screen";
    splitright = true;
    tabstop = 2;
    termguicolors = true;
    timeoutlen = 300;
    undofile = true;
    undolevels = 10000;
    updatetime = 200;
    virtualedit = "block";
    wildmode = "longest:full,full";
    winminwidth = 5;
    wrap = false;
  };

  globals = {
    snacks_animate = true;
    lazyvim_picker = "auto";
    lazyvim_cmp = "auto";
    ai_cmp = true;
    root_lsp_ignore = [ "copilot" ];
    deprecation_warnings = false;
    trouble_lualine = true;
    markdown_recommended_style = 0;
  };

  extraConfigLuaPre = ''
    -- shortmess flags appended (LazyVim parity)
    vim.opt.shortmess:append({ W = true, I = true, c = true, C = true })
  '';

  keymaps = [
    {
      mode = [ "n" "x" ];
      key = "j";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = { desc = "Down"; expr = true; silent = true; };
    }
    {
      mode = [ "n" "x" ];
      key = "<Down>";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = { desc = "Down"; expr = true; silent = true; };
    }
    {
      mode = [ "n" "x" ];
      key = "k";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = { desc = "Up"; expr = true; silent = true; };
    }
    {
      mode = [ "n" "x" ];
      key = "<Up>";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = { desc = "Up"; expr = true; silent = true; };
    }

    {
      mode = "n";
      key = "<C-h>";
      action = "<C-w>h";
      options = { desc = "Go to Left Window"; remap = true; };
    }
    {
      mode = "n";
      key = "<C-j>";
      action = "<C-w>j";
      options = { desc = "Go to Lower Window"; remap = true; };
    }
    {
      mode = "n";
      key = "<C-k>";
      action = "<C-w>k";
      options = { desc = "Go to Upper Window"; remap = true; };
    }
    {
      mode = "n";
      key = "<C-l>";
      action = "<C-w>l";
      options = { desc = "Go to Right Window"; remap = true; };
    }

    {
      mode = "n";
      key = "<C-Up>";
      action = "<cmd>resize +2<cr>";
      options.desc = "Increase Window Height";
    }
    {
      mode = "n";
      key = "<C-Down>";
      action = "<cmd>resize -2<cr>";
      options.desc = "Decrease Window Height";
    }
    {
      mode = "n";
      key = "<C-Left>";
      action = "<cmd>vertical resize -2<cr>";
      options.desc = "Decrease Window Width";
    }
    {
      mode = "n";
      key = "<C-Right>";
      action = "<cmd>vertical resize +2<cr>";
      options.desc = "Increase Window Width";
    }

    {
      mode = "n";
      key = "<A-j>";
      action = "<cmd>execute 'move .+' . v:count1<cr>==";
      options.desc = "Move Down";
    }
    {
      mode = "n";
      key = "<A-k>";
      action = "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==";
      options.desc = "Move Up";
    }
    {
      mode = "i";
      key = "<A-j>";
      action = "<esc><cmd>m .+1<cr>==gi";
      options.desc = "Move Down";
    }
    {
      mode = "i";
      key = "<A-k>";
      action = "<esc><cmd>m .-2<cr>==gi";
      options.desc = "Move Up";
    }
    {
      mode = "v";
      key = "<A-j>";
      action = '':<C-u>execute "'<,'>move '>+" . v:count1<cr>gv=gv'';
      options.desc = "Move Down";
    }
    {
      mode = "v";
      key = "<A-k>";
      action = '':<C-u>execute "'<,'>move '<-" . (v:count1 + 1)<cr>gv=gv'';
      options.desc = "Move Up";
    }

    {
      mode = "n";
      key = "<leader>bb";
      action = "<cmd>e #<cr>";
      options.desc = "Switch to Other Buffer";
    }
    {
      mode = "n";
      key = "<leader>`";
      action = "<cmd>e #<cr>";
      options.desc = "Switch to Other Buffer";
    }
    {
      mode = "n";
      key = "<leader>bd";
      action.__raw = "function() Snacks.bufdelete() end";
      options.desc = "Delete Buffer";
    }
    {
      mode = "n";
      key = "<leader>bo";
      action.__raw = "function() Snacks.bufdelete.other() end";
      options.desc = "Delete Other Buffers";
    }
    {
      mode = "n";
      key = "<leader>bD";
      action = "<cmd>:bd<cr>";
      options.desc = "Delete Buffer and Window";
    }

    {
      mode = "n";
      key = "n";
      action = "'Nn'[v:searchforward].'zv'";
      options = { expr = true; desc = "Next Search Result"; };
    }
    {
      mode = "x";
      key = "n";
      action = "'Nn'[v:searchforward]";
      options = { expr = true; desc = "Next Search Result"; };
    }
    {
      mode = "o";
      key = "n";
      action = "'Nn'[v:searchforward]";
      options = { expr = true; desc = "Next Search Result"; };
    }
    {
      mode = "n";
      key = "N";
      action = "'nN'[v:searchforward].'zv'";
      options = { expr = true; desc = "Prev Search Result"; };
    }
    {
      mode = "x";
      key = "N";
      action = "'nN'[v:searchforward]";
      options = { expr = true; desc = "Prev Search Result"; };
    }
    {
      mode = "o";
      key = "N";
      action = "'nN'[v:searchforward]";
      options = { expr = true; desc = "Prev Search Result"; };
    }

    {
      mode = "i";
      key = ",";
      action = ",<c-g>u";
    }
    {
      mode = "i";
      key = ".";
      action = ".<c-g>u";
    }
    {
      mode = "i";
      key = ";";
      action = ";<c-g>u";
    }

    {
      mode = [ "i" "x" "n" "s" ];
      key = "<C-s>";
      action = "<cmd>w<cr><esc>";
      options.desc = "Save File";
    }

    {
      mode = "n";
      key = "<leader>K";
      action = "<cmd>norm! K<cr>";
      options.desc = "Keywordprg";
    }

    {
      mode = "x";
      key = "<";
      action = "<gv";
    }
    {
      mode = "x";
      key = ">";
      action = ">gv";
    }

    {
      mode = "n";
      key = "gco";
      action = "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options.desc = "Add Comment Below";
    }
    {
      mode = "n";
      key = "gcO";
      action = "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>";
      options.desc = "Add Comment Above";
    }

    {
      mode = "n";
      key = "<leader>fn";
      action = "<cmd>enew<cr>";
      options.desc = "New File";
    }

    {
      mode = "n";
      key = "<leader>xl";
      action.__raw = ''
        function()
          local ok, err = pcall(vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 and vim.cmd.lclose or vim.cmd.lopen)
          if not ok and err then vim.notify(err, vim.log.levels.ERROR) end
        end
      '';
      options.desc = "Location List";
    }
    {
      mode = "n";
      key = "<leader>xq";
      action.__raw = ''
        function()
          local ok, err = pcall(vim.fn.getqflist({ winid = 0 }).winid ~= 0 and vim.cmd.cclose or vim.cmd.copen)
          if not ok and err then vim.notify(err, vim.log.levels.ERROR) end
        end
      '';
      options.desc = "Quickfix List";
    }
    {
      mode = "n";
      key = "[q";
      action.__raw = "vim.cmd.cprev";
      options.desc = "Previous Quickfix";
    }
    {
      mode = "n";
      key = "]q";
      action.__raw = "vim.cmd.cnext";
      options.desc = "Next Quickfix";
    }

    {
      mode = [ "n" "x" ];
      key = "<leader>cf";
      action.__raw = ''
        function()
          require("conform").format({ async = false, lsp_format = "fallback" })
        end
      '';
      options.desc = "Format";
    }

    {
      mode = "n";
      key = "<leader>cd";
      action.__raw = "vim.diagnostic.open_float";
      options.desc = "Line Diagnostics";
    }
    {
      mode = "n";
      key = "]d";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = vim.v.count1, float = true }) end
      '';
      options.desc = "Next Diagnostic";
    }
    {
      mode = "n";
      key = "[d";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = -vim.v.count1, float = true }) end
      '';
      options.desc = "Prev Diagnostic";
    }
    {
      mode = "n";
      key = "]e";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end
      '';
      options.desc = "Next Error";
    }
    {
      mode = "n";
      key = "[e";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.ERROR, float = true }) end
      '';
      options.desc = "Prev Error";
    }
    {
      mode = "n";
      key = "]w";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end
      '';
      options.desc = "Next Warning";
    }
    {
      mode = "n";
      key = "[w";
      action.__raw = ''
        function() vim.diagnostic.jump({ count = -vim.v.count1, severity = vim.diagnostic.severity.WARN, float = true }) end
      '';
      options.desc = "Prev Warning";
    }

    {
      mode = "n";
      key = "<leader>gg";
      action.__raw = ''
        function()
          if vim.fn.executable("lazygit") == 1 then
            Snacks.lazygit({ cwd = vim.fs.root(0, ".git") })
          end
        end
      '';
      options.desc = "Lazygit (Root Dir)";
    }
    {
      mode = "n";
      key = "<leader>gG";
      action.__raw = "function() if vim.fn.executable('lazygit') == 1 then Snacks.lazygit() end end";
      options.desc = "Lazygit (cwd)";
    }
    {
      mode = "n";
      key = "<leader>gL";
      action.__raw = "function() Snacks.picker.git_log() end";
      options.desc = "Git Log (cwd)";
    }
    {
      mode = "n";
      key = "<leader>gb";
      action.__raw = "function() Snacks.picker.git_log_line() end";
      options.desc = "Git Blame Line";
    }
    {
      mode = "n";
      key = "<leader>gf";
      action.__raw = "function() Snacks.picker.git_log_file() end";
      options.desc = "Git Current File History";
    }
    {
      mode = "n";
      key = "<leader>gl";
      action.__raw = ''
        function() Snacks.picker.git_log({ cwd = vim.fs.root(0, ".git") }) end
      '';
      options.desc = "Git Log";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>gB";
      action.__raw = "function() Snacks.gitbrowse() end";
      options.desc = "Git Browse (open)";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>gY";
      action.__raw = ''
        function()
          Snacks.gitbrowse({ open = function(url) vim.fn.setreg("+", url) end, notify = false })
        end
      '';
      options.desc = "Git Browse (copy)";
    }

    {
      mode = "n";
      key = "<leader>qq";
      action = "<cmd>qa<cr>";
      options.desc = "Quit All";
    }

    {
      mode = "n";
      key = "<leader>ui";
      action.__raw = "vim.show_pos";
      options.desc = "Inspect Pos";
    }
    {
      mode = "n";
      key = "<leader>uI";
      action.__raw = ''
        function() vim.treesitter.inspect_tree() vim.api.nvim_input("I") end
      '';
      options.desc = "Inspect Tree";
    }

    {
      mode = "n";
      key = "<leader>-";
      action = "<C-W>s";
      options = { desc = "Split Window Below"; remap = true; };
    }
    {
      mode = "n";
      key = "<leader>|";
      action = "<C-W>v";
      options = { desc = "Split Window Right"; remap = true; };
    }
    {
      mode = "n";
      key = "<leader>wd";
      action = "<C-W>c";
      options = { desc = "Delete Window"; remap = true; };
    }

    {
      mode = "n";
      key = "<leader><tab>l";
      action = "<cmd>tablast<cr>";
      options.desc = "Last Tab";
    }
    {
      mode = "n";
      key = "<leader><tab>o";
      action = "<cmd>tabonly<cr>";
      options.desc = "Close Other Tabs";
    }
    {
      mode = "n";
      key = "<leader><tab>f";
      action = "<cmd>tabfirst<cr>";
      options.desc = "First Tab";
    }
    {
      mode = "n";
      key = "<leader><tab><tab>";
      action = "<cmd>tabnew<cr>";
      options.desc = "New Tab";
    }
    {
      mode = "n";
      key = "<leader><tab>]";
      action = "<cmd>tabnext<cr>";
      options.desc = "Next Tab";
    }
    {
      mode = "n";
      key = "<leader><tab>d";
      action = "<cmd>tabclose<cr>";
      options.desc = "Close Tab";
    }
    {
      mode = "n";
      key = "<leader><tab>[";
      action = "<cmd>tabprevious<cr>";
      options.desc = "Previous Tab";
    }

    {
      mode = "c";
      key = "<S-Enter>";
      action.__raw = "function() require('noice').redirect(vim.fn.getcmdline()) end";
      options.desc = "Redirect Cmdline";
    }
    {
      mode = "n";
      key = "<leader>snl";
      action.__raw = "function() require('noice').cmd('last') end";
      options.desc = "Noice Last Message";
    }
    {
      mode = "n";
      key = "<leader>snh";
      action.__raw = "function() require('noice').cmd('history') end";
      options.desc = "Noice History";
    }
    {
      mode = "n";
      key = "<leader>sna";
      action.__raw = "function() require('noice').cmd('all') end";
      options.desc = "Noice All";
    }
    {
      mode = "n";
      key = "<leader>snd";
      action.__raw = "function() require('noice').cmd('dismiss') end";
      options.desc = "Dismiss All";
    }
    {
      mode = "n";
      key = "<leader>snt";
      action.__raw = "function() require('noice').cmd('pick') end";
      options.desc = "Noice Picker";
    }
    {
      mode = [ "i" "n" "s" ];
      key = "<c-f>";
      action.__raw = ''
        function() if not require('noice.lsp').scroll(4) then return '<c-f>' end end
      '';
      options = { silent = true; expr = true; desc = "Scroll Forward"; };
    }
    {
      mode = [ "i" "n" "s" ];
      key = "<c-b>";
      action.__raw = ''
        function() if not require('noice.lsp').scroll(-4) then return '<c-b>' end end
      '';
      options = { silent = true; expr = true; desc = "Scroll Backward"; };
    }
  ];

  autoCmd = [
    {
      event = [ "FocusGained" "TermClose" "TermLeave" ];
      callback.__raw = ''
        function()
          if vim.o.buftype ~= "nofile" then
            vim.cmd("checktime")
          end
        end
      '';
    }
    {
      event = [ "TextYankPost" ];
      callback.__raw = ''
        function()
          (vim.hl or vim.highlight).on_yank()
        end
      '';
    }
    {
      event = [ "VimResized" ];
      callback.__raw = ''
        function()
          local current_tab = vim.fn.tabpagenr()
          vim.cmd("tabdo wincmd =")
          vim.cmd("tabnext " .. current_tab)
        end
      '';
    }
    {
      event = [ "BufReadPost" ];
      callback.__raw = ''
        function(event)
          local exclude = { "gitcommit" }
          local buf = event.buf
          if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
            return
          end
          vim.b[buf].lazyvim_last_loc = true
          local mark = vim.api.nvim_buf_get_mark(buf, '"')
          local lcount = vim.api.nvim_buf_line_count(buf)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [
        "PlenaryTestPopup"
        "checkhealth"
        "dap-float"
        "dbout"
        "gitsigns-blame"
        "grug-far"
        "help"
        "lspinfo"
        "neotest-output"
        "neotest-output-panel"
        "neotest-summary"
        "notify"
        "qf"
        "spectre_panel"
        "startuptime"
        "tsplayground"
      ];
      callback.__raw = ''
        function(event)
          vim.bo[event.buf].buflisted = false
          vim.schedule(function()
            vim.keymap.set("n", "q", function()
              vim.cmd("close")
              pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
            end, { buffer = event.buf, silent = true, desc = "Quit buffer" })
          end)
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [ "man" ];
      callback.__raw = ''
        function(event) vim.bo[event.buf].buflisted = false end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [ "text" "plaintex" "typst" "gitcommit" "markdown" ];
      callback.__raw = ''
        function()
          vim.opt_local.wrap = true
          vim.opt_local.spell = true
        end
      '';
    }
    {
      event = [ "FileType" ];
      pattern = [ "json" "jsonc" "json5" ];
      callback.__raw = ''
        function() vim.opt_local.conceallevel = 0 end
      '';
    }
    {
      event = [ "BufWritePre" ];
      callback.__raw = ''
        function(event)
          if event.match:match("^%w%w+:[\\/][\\/]") then return end
          local file = vim.uv.fs_realpath(event.match) or event.match
          vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
        end
      '';
    }
  ];

  extraConfigLuaPost = ''
    -- LazyVim parity: snacks toggle keymaps
    if package.loaded["snacks"] and Snacks and Snacks.toggle then
      Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
      Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
      Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
      Snacks.toggle.diagnostics():map("<leader>ud")
      Snacks.toggle.line_number():map("<leader>ul")
      Snacks.toggle.option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2, name = "Conceal Level" }):map("<leader>uc")
      Snacks.toggle.option("showtabline", { off = 0, on = vim.o.showtabline > 0 and vim.o.showtabline or 2, name = "Tabline" }):map("<leader>uA")
      Snacks.toggle.treesitter():map("<leader>uT")
      Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
      if Snacks.toggle.dim then Snacks.toggle.dim():map("<leader>uD") end
      if Snacks.toggle.animate then Snacks.toggle.animate():map("<leader>ua") end
      if Snacks.toggle.indent then Snacks.toggle.indent():map("<leader>ug") end
      if Snacks.toggle.scroll then Snacks.toggle.scroll():map("<leader>uS") end
      if Snacks.toggle.zoom then Snacks.toggle.zoom():map("<leader>wm"):map("<leader>uZ") end
      if Snacks.toggle.zen then Snacks.toggle.zen():map("<leader>uz") end
      if Snacks.toggle.profiler then
        Snacks.toggle.profiler():map("<leader>dpp")
        Snacks.toggle.profiler_highlights():map("<leader>dph")
      end
      if vim.lsp.inlay_hint then
        Snacks.toggle.inlay_hints():map("<leader>uh")
      end
    end

    -- Snacks picker keymaps (LazyVim parity)
    if package.loaded["snacks"] and Snacks and Snacks.picker then
      local function map(key, fn, desc)
        vim.keymap.set("n", key, fn, { desc = desc, silent = true })
      end
      local root = function() return vim.fs.root(0, { ".git", "lua" }) or vim.fn.getcwd() end
      map("<leader><space>", function() Snacks.picker.files() end, "Find Files")
      map("<leader>ff", function() Snacks.picker.files() end, "Find Files")
      map("<leader>fF", function() Snacks.picker.files({ root = false }) end, "Find Files (cwd)")
      map("<leader>fr", function() Snacks.picker.recent() end, "Recent")
      map("<leader>fb", function() Snacks.picker.buffers() end, "Buffers")
      map("<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, "Find Config File")
      map("<leader>,", function() Snacks.picker.buffers() end, "Buffers")
      map("<leader>/", function() Snacks.picker.grep() end, "Grep")
      map("<leader>:", function() Snacks.picker.command_history() end, "Command History")
      map("<leader>sg", function() Snacks.picker.grep() end, "Grep")
      map("<leader>sw", function() Snacks.picker.grep_word() end, "Visual selection or word")
      map("<leader>sb", function() Snacks.picker.lines() end, "Buffer Lines")
      map("<leader>sB", function() Snacks.picker.grep_buffers() end, "Grep Open Buffers")
      map("<leader>sk", function() Snacks.picker.keymaps() end, "Keymaps")
      map("<leader>sm", function() Snacks.picker.marks() end, "Marks")
      map("<leader>sR", function() Snacks.picker.resume() end, "Resume")
      map("<leader>sd", function() Snacks.picker.diagnostics() end, "Diagnostics")
      map("<leader>sh", function() Snacks.picker.help() end, "Help Pages")
      map("<leader>sH", function() Snacks.picker.highlights() end, "Highlights")
      map("<leader>sj", function() Snacks.picker.jumps() end, "Jumps")
      map("<leader>sl", function() Snacks.picker.loclist() end, "Location List")
      map("<leader>sM", function() Snacks.picker.man() end, "Man Pages")
      map("<leader>sq", function() Snacks.picker.qflist() end, "Quickfix List")
      map("<leader>sC", function() Snacks.picker.commands() end, "Commands")
      map("<leader>su", function() Snacks.picker.undo() end, "Undo History")
      map("<leader>uC", function() Snacks.picker.colorschemes() end, "Colorschemes")
      map("<leader>ss", function() Snacks.picker.lsp_symbols() end, "LSP Symbols")
      map("<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, "LSP Workspace Symbols")
      map("gd", function() Snacks.picker.lsp_definitions() end, "Goto Definition")
      map("gr", function() Snacks.picker.lsp_references() end, "References")
      map("gI", function() Snacks.picker.lsp_implementations() end, "Goto Implementation")
      map("gy", function() Snacks.picker.lsp_type_definitions() end, "Goto Type Definition")
    end
  '';
}
