-- nvim only sends the LSP shutdown handshake on a clean exit, and not every
-- server honours the `processId` it is given, so some outlive it. PR_SET_PDEATHSIG
-- needs no cooperation and still fires on SIGKILL. Patched here rather than in
-- each `cmd`, because nvim derives a server's name from cmd[1].
if vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1 then
  local rpc_start = vim.lsp.rpc.start
  vim.lsp.rpc.start = function(cmd, dispatchers, extra)
    if type(cmd) == "table" and cmd[1] ~= "setpriv" then
      cmd = vim.list_extend({ "setpriv", "--pdeathsig=TERM", "--" }, vim.deepcopy(cmd))
    end
    return rpc_start(cmd, dispatchers, extra)
  end
end

-- A repo pinning an older toolchain should analyse with the version it expects.
local function project_bin(name, args)
  args = args or { "--stdio" }
  return function(dispatchers, config)
    local cmd = name
    if (config or {}).root_dir then
      local local_cmd = vim.fs.joinpath(config.root_dir, "node_modules/.bin", name)
      if vim.fn.executable(local_cmd) == 1 then
        cmd = local_cmd
      end
    end
    return vim.lsp.rpc.start(vim.list_extend({ cmd }, args), dispatchers)
  end
end

local function vue_typescript_plugin()
  local exe = vim.fn.exepath("vue-language-server")
  if exe == "" then
    return nil
  end
  local root = vim.fs.dirname(vim.fs.dirname(vim.uv.fs_realpath(exe) or exe))
  local dir = vim.fs.joinpath(root, "lib/language-tools/packages/language-server")
  return vim.fn.isdirectory(dir) == 1 and dir or nil
end

local nixd = require("nixd")

-- A panic in phpantom leaves its symbol map unusable rather than exiting the process, so nvim
-- keeps a client that answers definition and references with nothing for the rest of the session.
-- Set by the stderr watchdog below, cleared by the server's `on_exit`, which is where the restart
-- has to happen: re-enabling before the old client is gone just hands the dead one back.
local phpantom_restarting = false

local servers = {
  nixd = {
    cmd = { "nixd" },
    filetypes = { "nix" },
    root_markers = { "flake.nix", ".git" },
    settings = {
      nixd = {
        formatting = { command = { "nixfmt" } },
        nixpkgs = { expr = "import <nixpkgs> { }" },
      },
    },
    before_init = function(params, config)
      local folder = params.workspaceFolders and params.workspaceFolders[1]
      local root = (folder and vim.uri_to_fname(folder.uri)) or (params.rootUri and vim.uri_to_fname(params.rootUri))
      if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then
        return
      end
      -- In place: vim.lsp.Client captures this reference at create() time.
      config.settings = config.settings or {}
      config.settings.nixd = vim.tbl_deep_extend("force", config.settings.nixd or {}, nixd.settings(root))
      config.settings.nixd_root = root
    end,
  },

  phpantom_lsp = {
    cmd = { "phpantom_lsp" },
    filetypes = { "php", "blade" },
    root_markers = { ".phpantom.toml", "composer.json", ".git" },
    -- ponytail: 0.10.0 slices the document with stale symbol-map offsets while serving
    -- semanticTokens/full after an edit -- `symbol_map/mod.rs:217: start byte index N is out
    -- of bounds`. The panic is caught, but leaves the map dead, so definition and references
    -- silently return nothing for the rest of the session. Its tokens are sparse and go empty
    -- after the first edit anyway; treesitter highlights php. Drop the capability when upstream
    -- fixes the slice.
    on_init = function(client)
      client.server_capabilities.semanticTokensProvider = nil
    end,
    on_exit = function()
      if not phpantom_restarting then
        return
      end
      phpantom_restarting = false
      vim.schedule(function()
        vim.lsp.enable("phpantom_lsp")
      end)
    end,
  },

  tsc = {
    cmd = { "tsc", "--lsp", "--stdio" },
    filetypes = {
      "javascript",
      "javascriptreact",
      "javascript.jsx",
      "typescript",
      "typescriptreact",
      "typescript.tsx",
    },
    root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
  },

  vue_ls = {
    cmd = { "vue-language-server", "--stdio" },
    filetypes = { "vue" },
    root_markers = { "package.json", ".git" },
    on_init = function(client)
      client.handlers["tsserver/request"] = function(_, result, context)
        local ts = vim.lsp.get_clients({ bufnr = context.bufnr, name = "vtsls" })[1]
        if not ts then
          vim.notify("vue_ls needs the vtsls client to answer TypeScript requests", vim.log.levels.ERROR)
          return
        end
        local param = type(result[1]) == "table" and result[1] or result
        local id, command, payload = unpack(param)
        ts:exec_cmd({
          title = "vue_request_forward",
          command = "typescript.tsserverRequest",
          arguments = { command, payload },
        }, { bufnr = context.bufnr }, function(_, r)
          client:notify("tsserver/response", { id, r and r.body })
        end)
      end
    end,
  },

  vtsls = {
    cmd = { "vtsls", "--stdio" },
    filetypes = { "vue" },
    root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
    settings = {
      vtsls = {
        tsserver = {
          globalPlugins = {
            {
              name = "@vue/typescript-plugin",
              location = vue_typescript_plugin(),
              languages = { "vue" },
              configNamespace = "typescript",
            },
          },
        },
      },
    },
  },

  svelte = {
    cmd = project_bin("svelteserver"),
    filetypes = { "svelte" },
    root_markers = { "svelte.config.js", "package.json", ".git" },
  },

  oxlint = {
    cmd = { "oxlint", "--lsp" },
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
      "svelte",
      "astro",
    },
    root_markers = { ".oxlintrc.json", "package.json", ".git" },
  },

  oxfmt = {
    cmd = project_bin("oxfmt", { "--lsp" }),
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
      "svelte",
      "astro",
      "json",
      "jsonc",
      "css",
      "scss",
    },
    root_markers = { "package.json", ".git" },
  },

  html = {
    cmd = { "vscode-html-language-server", "--stdio" },
    filetypes = { "html", "htm", "templ", "tmpl", "blade", "twig" },
    root_markers = { "package.json", ".git" },
    init_options = {
      provideFormatter = false, -- prettier does this
      embeddedLanguages = { css = true, javascript = true },
      configurationSection = { "html", "css", "javascript" },
    },
  },
  cssls = {
    cmd = { "vscode-css-language-server", "--stdio" },
    filetypes = { "css", "scss", "less" },
    root_markers = { "package.json", ".git" },
    init_options = { provideFormatter = false },
    settings = {
      css = { validate = true, lint = { unknownAtRules = "ignore" } },
      scss = { validate = true, lint = { unknownAtRules = "ignore" } },
    },
  },
  jsonls = {
    cmd = { "vscode-json-language-server", "--stdio" },
    filetypes = { "json", "jsonc" },
    root_markers = { ".git" },
    init_options = { provideFormatter = false },
  },
  yamlls = {
    cmd = { "yaml-language-server", "--stdio" },
    filetypes = { "yaml", "yaml.docker-compose" },
    root_markers = { ".git" },
    settings = { yaml = { keyOrdering = false } },
  },
  taplo = {
    cmd = { "taplo", "lsp", "stdio" },
    filetypes = { "toml" },
    root_markers = { ".git" },
  },
  marksman = {
    cmd = { "marksman", "server" },
    filetypes = { "markdown", "markdown.mdx" },
    root_markers = { ".marksman.toml", ".git" },
  },

  sqruff = {
    cmd = { "sqruff", "lsp" },
    filetypes = { "sql", "pgsql", "mysql" },
    root_markers = { ".sqruff", ".sqlfluff", ".git" },
  },

  gopls = {
    cmd = { "gopls" },
    filetypes = { "go", "gomod", "gowork", "gotmpl" },
    root_markers = { "go.work", "go.mod", ".git" },
    settings = {
      gopls = {
        gofumpt = true,
        analyses = { unusedparams = true, shadow = true },
        staticcheck = true,
      },
    },
  },
  golangci_lint_ls = {
    cmd = { "golangci-lint-langserver" },
    filetypes = { "go", "gomod" },
    root_markers = { ".golangci.yml", ".golangci.yaml", "go.mod", ".git" },
    init_options = { command = { "golangci-lint", "run", "--output.json.path", "stdout" } },
  },
  templ = {
    cmd = { "templ", "lsp" },
    filetypes = { "templ" },
    root_markers = { "go.mod", ".git" },
    settings = { templ = { enable_snippets = true } },
  },

  ty = {
    cmd = { "ty", "server" },
    filetypes = { "python" },
    root_markers = { "ty.toml", "pyproject.toml", "setup.py", "requirements.txt", ".git" },
  },
  ruff = {
    cmd = { "ruff", "server" },
    filetypes = { "python" },
    root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
  },

  bashls = {
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash", "zsh" },
    root_markers = { ".git" },
  },
  docker_language_server = {
    cmd = { "docker-language-server", "start", "--stdio" },
    filetypes = { "dockerfile", "yaml.docker-compose" },
    root_markers = {
      "Dockerfile",
      "docker-compose.yaml",
      "docker-compose.yml",
      "compose.yaml",
      "compose.yml",
      ".git",
    },
  },
  clangd = {
    cmd = { "clangd", "--background-index", "--clang-tidy", "--header-insertion=iwyu" },
    filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
    root_markers = { "compile_commands.json", "compile_flags.txt", ".clangd", ".git" },
  },
  lemminx = {
    cmd = { "lemminx" },
    filetypes = { "xml", "xsd", "xsl", "xslt", "svg" },
    root_markers = { ".git" },
    settings = { xml = { format = { enabled = false } } },
  },
  terraformls = {
    cmd = { "terraform-ls", "serve" },
    filetypes = { "terraform", "terraform-vars" },
    root_markers = { ".terraform", "main.tf", ".git" },
  },

  lua_ls = {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_markers = { ".luarc.json", ".luarc.jsonc", "stylua.toml", ".git" },
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
}

-- Server stderr reaches nvim only as a log call, so that is where a panic can be noticed.
local log_error = vim.lsp.log.error
vim.lsp.log.error = function(...)
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    if type(arg) == "string" and arg:find("panic", 1, true) and arg:find("phpantom", 1, true) then
      if not phpantom_restarting then
        phpantom_restarting = true
        vim.schedule(function()
          vim.notify("phpantom_lsp panicked - restarting", vim.log.levels.WARN)
          -- Forced: phpantom ignores the shutdown handshake, and a client left waiting on it
          -- stays attached and dead.
          for _, client in ipairs(vim.lsp.get_clients({ name = "phpantom_lsp" })) do
            client:stop(true)
          end
        end)
      end
      break
    end
  end
  return log_error(...)
end

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})

for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
end
vim.lsp.enable(vim.tbl_keys(servers))

vim.g.rustaceanvim = {
  server = {
    default_settings = {
      ["rust-analyzer"] = {
        cargo = { allFeatures = true },
        checkOnSave = true,
        check = { command = "clippy" },
      },
    },
  },
}

local function code_action(only, apply)
  return function()
    vim.lsp.buf.code_action({
      apply = apply,
      context = { only = { only }, diagnostics = {} },
    })
  end
end

local function rename_file()
  local buf = vim.api.nvim_get_current_buf()
  local old = vim.api.nvim_buf_get_name(buf)
  if old == "" or vim.bo[buf].buftype ~= "" then
    return
  end

  vim.ui.input({ prompt = "New file name: ", default = old, completion = "file" }, function(input)
    if not input or input == "" or input == old then
      return
    end

    local new = vim.fs.normalize(input)
    vim.fn.mkdir(vim.fs.dirname(new), "p")

    local clients = vim.lsp.get_clients({ bufnr = buf })
    local files = { { oldUri = vim.uri_from_fname(old), newUri = vim.uri_from_fname(new) } }

    for _, client in ipairs(clients) do
      if client:supports_method("workspace/willRenameFiles") then
        local res = client:request_sync("workspace/willRenameFiles", { files = files }, 1000, buf)
        if res and res.result then
          vim.lsp.util.apply_workspace_edit(res.result, client.offset_encoding)
        end
      end
    end

    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! write")
    end)

    local ok, err = vim.uv.fs_rename(old, new)
    if not ok then
      vim.notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    vim.api.nvim_buf_set_name(buf, new)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! write!")
      vim.cmd("silent! edit")
    end)

    for _, client in ipairs(clients) do
      if client:supports_method("workspace/didRenameFiles") then
        client:notify("workspace/didRenameFiles", { files = files })
      end
    end
  end)
end

-- Snacks.words without snacks: documentHighlight gives the ranges, so jumping
-- between them is a sort and an index.
local function reference_jump(count, cycle)
  return function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" })[1]
    if not client then
      return
    end

    local function byte(line, character)
      local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
      local ok, col = pcall(vim.str_byteindex, text, client.offset_encoding, character, false)
      return ok and col or character
    end

    client:request(
      "textDocument/documentHighlight",
      vim.lsp.util.make_position_params(win, client.offset_encoding),
      function(_, result)
        if not result or #result == 0 then
          return
        end

        local positions = vim.tbl_map(function(hl)
          return hl.range.start
        end, result)
        table.sort(positions, function(a, b)
          if a.line == b.line then
            return a.character < b.character
          end
          return a.line < b.line
        end)

        local cursor = vim.api.nvim_win_get_cursor(win)
        local current = 1
        for i, pos in ipairs(positions) do
          if pos.line < cursor[1] - 1 or (pos.line == cursor[1] - 1 and byte(pos.line, pos.character) <= cursor[2]) then
            current = i
          end
        end

        local target = current + count * vim.v.count1
        if cycle then
          target = (target - 1) % #positions + 1
        else
          target = math.min(math.max(target, 1), #positions)
        end

        local pos = positions[target]
        vim.api.nvim_win_set_cursor(win, { pos.line + 1, byte(pos.line, pos.character) })
      end,
      buf
    )
  end
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
  callback = function(args)
    local buf = args.buf
    local function map(mode, lhs, rhs, desc, opts)
      vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = buf, desc = desc }, opts or {}))
    end

    local function pick(fn, opts)
      return function()
        require("fzf-lua")[fn](opts)
      end
    end

    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if client and client.name == "nixd" and (client.settings or {}).nixd_root then
      nixd.warm(client.settings.nixd_root, client)
    end

    if client and client:supports_method("textDocument/documentColor") then
      vim.lsp.document_color.enable(true, { bufnr = buf })
    end

    if client and client:supports_method("textDocument/linkedEditingRange") then
      vim.lsp.linked_editing_range.enable(true, { bufnr = buf })
    end

    map("n", "gd", pick("lsp_definitions", { jump1 = true }), "Goto definition")
    map("n", "gD", vim.lsp.buf.declaration, "Goto declaration")
    map("n", "gr", pick("lsp_references", { ignore_current_line = true }), "References", { nowait = true })
    map("n", "gI", pick("lsp_implementations", { jump1 = true }), "Goto implementation")
    map("n", "gy", pick("lsp_typedefs", { jump1 = true }), "Goto type definition")
    map("n", "K", vim.lsp.buf.hover, "Hover") -- border comes from 'winborder'

    if client and client:supports_method("textDocument/signatureHelp") then
      map("n", "gK", vim.lsp.buf.signature_help, "Signature help")
      map("i", "<c-k>", vim.lsp.buf.signature_help, "Signature help")
    end

    map("n", "<leader>cl", "<cmd>checkhealth vim.lsp<cr>", "LSP info")
    map({ "n", "x" }, "<leader>ca", pick("lsp_code_actions"), "Code action")
    map("n", "<leader>cA", code_action("source", false), "Source action")
    map("n", "<leader>co", code_action("source.organizeImports", true), "Organize imports")
    map("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
    map("n", "<leader>cR", rename_file, "Rename file")
    map("n", "<leader>cs", "<cmd>Trouble symbols toggle<cr>", "Symbols (Trouble)")
    map("n", "<leader>cS", "<cmd>Trouble lsp toggle<cr>", "LSP references/definitions (Trouble)")

    if client and client:supports_method("textDocument/codeLens") then
      map({ "n", "x" }, "<leader>cc", vim.lsp.codelens.run, "Run codelens")
      map("n", "<leader>cC", vim.lsp.codelens.refresh, "Refresh codelens")
    end

    vim.lsp.inlay_hint.enable(false, { bufnr = buf })

    if client and client:supports_method("textDocument/documentHighlight") then
      map("n", "]]", reference_jump(1), "Next reference")
      map("n", "[[", reference_jump(-1), "Prev reference")
      map("n", "<a-n>", reference_jump(1, true), "Next reference")
      map("n", "<a-p>", reference_jump(-1, true), "Prev reference")

      local group = vim.api.nvim_create_augroup("lsp_highlight_" .. buf, { clear = true })
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        buffer = buf,
        group = group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
        buffer = buf,
        group = group,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})
