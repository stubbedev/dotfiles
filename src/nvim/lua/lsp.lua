
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

local nixd = require("nixd")


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
  },

  tsgo = {
    cmd = { "tsgo", "--lsp", "--stdio" },
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
        checkOnSave = { command = "clippy" },
      },
    },
  },
}

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
  callback = function(args)
    local buf = args.buf
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
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

    map("n", "grd", vim.lsp.buf.definition, "Go to definition")
    map("n", "K", vim.lsp.buf.hover, "Hover") -- border comes from 'winborder'

    vim.lsp.inlay_hint.enable(false, { bufnr = buf })
    map("n", "<leader>uh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
    end, "Toggle inlay hints")

    if client and client:supports_method("textDocument/documentHighlight") then
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
