-- Language servers, via nvim 0.12's native vim.lsp.config/enable. No
-- nvim-lspconfig: every server below states its own cmd, filetypes and root
-- markers, so what runs for a given buffer is readable off this page.
--
-- Every binary comes from the nix wrapper's PATH (modules/nvim.nix).

-- Language servers outlive nvim whenever it dies without a clean :qa -- a
-- closed terminal, a killed tmux pane, SIGTERM, a crash. nvim only sends the
-- LSP shutdown handshake on a clean exit, and servers are supposed to watch
-- the `processId` they get in initialize and quit when it disappears.
-- phpantom_lsp doesn't, and it idles at ~850MB, so every unclean exit in a PHP
-- repo leaked that much until reboot.
--
-- setpriv(1) sets PR_SET_PDEATHSIG before exec, so the kernel signals the
-- server the moment nvim's process dies -- no cooperation from the server, and
-- it still fires when nvim is SIGKILLed. Patch vim.lsp.rpc.start rather than
-- each `cmd`: nvim derives a server's default name from cmd[1], which would
-- otherwise become "setpriv".
if vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1 then
  local rpc_start = vim.lsp.rpc.start
  vim.lsp.rpc.start = function(cmd, dispatchers, extra)
    if type(cmd) == "table" and cmd[1] ~= "setpriv" then
      cmd = vim.list_extend({ "setpriv", "--pdeathsig=TERM", "--" }, vim.deepcopy(cmd))
    end
    return rpc_start(cmd, dispatchers, extra)
  end
end

-- Prefer a project's own node_modules/.bin copy of a server over the nix one,
-- so a repo pinning an older toolchain analyses with the version it expects.
-- `args` differs per server: most speak `--stdio`, oxfmt wants `--lsp`.
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

-- Servers -------------------------------------------------------------------

local servers = {
  -- Nix
  nixd = {
    cmd = { "nixd" },
    filetypes = { "nix" },
    root_markers = { "flake.nix", ".git" },
    settings = {
      nixd = {
        formatting = { command = { "nixfmt" } },
        nixpkgs = { expr = "import <nixpkgs> { }" },
        -- `with` shadows free vars in nested scopes; nixd warns aggressively,
        -- drowning out real diagnostics.
        diagnostic = { suppress = { "sema-escaping-with" } },
      },
    },
    -- Reads the cache only -- no `nix eval` on this path, so opening a .nix
    -- file never waits. Anything not cached is filled in by warm_nixd() from
    -- the LspAttach handler below.
    before_init = function(params, config)
      local folder = params.workspaceFolders and params.workspaceFolders[1]
      local root = (folder and vim.uri_to_fname(folder.uri)) or (params.rootUri and vim.uri_to_fname(params.rootUri))
      if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then
        return
      end
      -- Mutate config.settings in place: vim.lsp.Client captures a reference at
      -- create() time, so reassigning the table here would be ignored.
      config.settings = config.settings or {}
      config.settings.nixd = vim.tbl_deep_extend("force", config.settings.nixd or {}, nixd.settings(root))
      config.settings.nixd_root = root
    end,
  },

  -- PHP. phpantom already understands Blade -- its binary carries the whole
  -- directive table (@section, @forelse, @component, ...) and knows
  -- resources/views -- it was only ever registered for `php` upstream.
  phpantom_lsp = {
    cmd = { "phpantom_lsp" },
    filetypes = { "php", "blade" },
    root_markers = { ".phpantom.toml", "composer.json", ".git" },
  },

  -- TypeScript / JavaScript / React. One Go binary; no node, no tsserver.
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

  -- Vue v3 is self-contained: it bridges to tsgo internally, so it needs no
  -- tsserver plugin and no second TypeScript server alongside it.
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

  -- Web
  -- Not attached to plain `php`: the server is a 143MB node process, and in
  -- this codebase 20 of 6588 non-blade .php files contain any HTML at all --
  -- the templates are all .blade.php, which is still covered.
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

  -- SQL. sqruff is one Rust binary doing lint, format and LSP, with real
  -- dialect support; put `.sqruff` in a repo to pick postgres/sqlite/mysql.
  sqruff = {
    cmd = { "sqruff", "lsp" },
    filetypes = { "sql", "pgsql", "mysql" },
    root_markers = { ".sqruff", ".sqlfluff", ".git" },
  },

  -- Go
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

  -- Python: ruff lints and formats, ty type-checks. Both are Astral's and both
  -- are Rust, replacing basedpyright -- a 153MB node process -- with 14MB.
  -- ty is pre-1.0; if its type checking ever disagrees with reality, swapping
  -- back to basedpyright is this block plus one line in modules/nvim.nix.
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

  -- Shell, containers, lua
  bashls = {
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash", "zsh" },
    root_markers = { ".git" },
  },
  -- Docker's own Go server, covering Dockerfile *and* compose. Replaces
  -- dockerfile-language-server and docker-compose-language-service, which were
  -- two separate node processes at 70MB and 71MB.
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

-- blink drives completion, so every server must advertise its capabilities.
vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})

for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
end
vim.lsp.enable(vim.tbl_keys(servers))

-- rust-analyzer is driven by rustaceanvim, which owns its own client.
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

-- Keymaps that only make sense once a server is attached.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp_attach", { clear = true }),
  callback = function(args)
    local buf = args.buf
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end

    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- nixd: if this flake's configuration names weren't cached, resolve them in
    -- the background and push them to the running server. Never blocks.
    if client and client.name == "nixd" and (client.settings or {}).nixd_root then
      nixd.warm(client.settings.nixd_root, client)
    end

    -- Colour swatches inline for any server that reports them -- cssls,
    -- vue_ls and html all do, so hex/rgb values in CSS render as the colour.
    if client and client:supports_method("textDocument/documentColor") then
      vim.lsp.document_color.enable(true, { bufnr = buf })
    end

    -- Editing an opening tag edits its closing tag at the same time. Supported
    -- by vue_ls, tsgo and html. This is not the same thing as nvim-ts-autotag,
    -- which *inserts* the closing tag -- these are complementary.
    if client and client:supports_method("textDocument/linkedEditingRange") then
      vim.lsp.linked_editing_range.enable(true, { bufnr = buf })
    end

    -- grn, gra, grr, gri, grt, grx and gO are Neovim 0.12 defaults; only what
    -- it doesn't already bind belongs here.
    map("n", "grd", vim.lsp.buf.definition, "Go to definition")
    map("n", "K", vim.lsp.buf.hover, "Hover") -- border comes from 'winborder'

    -- Inlay hints off by default: they reflow the line as you type.
    -- <leader>uh toggles them per buffer.
    vim.lsp.inlay_hint.enable(false, { bufnr = buf })
    map("n", "<leader>uh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
    end, "Toggle inlay hints")

    -- Highlight the symbol under the cursor. This is what vim-illuminate did,
    -- except it's a built-in LSP request and costs nothing when idle.
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
