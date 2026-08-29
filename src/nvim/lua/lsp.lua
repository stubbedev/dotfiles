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

-- nixd ----------------------------------------------------------------------
--
-- nixd attaches per-flake. Feeding it `nixosConfigurations.<host>.options` and
-- `homeConfigurations.<user>.options` is what makes completion able to index
-- into the right host/user. Discovering the right names needs `nix eval`,
-- 2-3s on a cold flake -- enough to visibly hang the first .nix file of the
-- day -- so the picked names are cached to ~/.cache/nvim/nixd-roots.json,
-- keyed by flake root. Only the very first open per repo pays.

local cache_path = vim.fn.stdpath("cache") .. "/nixd-roots.json"
local nixd_eval_cache = {}

local function load_disk_cache()
  if vim.fn.filereadable(cache_path) == 0 then
    return {}
  end
  local lines = vim.fn.readfile(cache_path)
  if not lines or #lines == 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  return (ok and type(data) == "table") and data or {}
end

local disk_cache = load_disk_cache()

local function save_disk_cache()
  local ok, encoded = pcall(vim.json.encode, disk_cache)
  if not ok then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(cache_path, ":h"), "p")
  vim.fn.writefile({ encoded }, cache_path)
end

local function nixd_eval(root, attr, apply)
  local key = root .. "::" .. attr .. "::" .. (apply or "")
  if nixd_eval_cache[key] ~= nil then
    return nixd_eval_cache[key]
  end
  local cmd = { "nix", "eval", "--json", "--no-warn-dirty", root .. "#" .. attr }
  if apply then
    table.insert(cmd, "--apply")
    table.insert(cmd, apply)
  end
  local out = vim.fn.system(cmd)
  local result = nil
  if vim.v.shell_error == 0 then
    local ok, parsed = pcall(vim.json.decode, out)
    if ok then
      result = parsed
    end
  end
  nixd_eval_cache[key] = result
  return result
end

local function nixd_pick(root, attr, identity_attr)
  local names = nixd_eval(root, attr, "builtins.attrNames")
  if type(names) ~= "table" or #names == 0 then
    return nil
  end

  local map = nixd_eval(root, attr, "cs: builtins.mapAttrs (_: c: c." .. identity_attr .. ") cs")
  if type(map) == "table" then
    local hostname = vim.uv.os_gethostname()
    local user = vim.env.USER or ""
    for _, want in ipairs({ hostname, user .. "@" .. hostname, user }) do
      for name, ident in pairs(map) do
        if ident == want then
          return name
        end
      end
    end
  end

  local function looks_disposable(name)
    return name:match("[Ii]nstaller") or name:match("[Ii]so") or name:match("[Ll]ive")
  end
  local fallback
  for _, name in ipairs(names) do
    if not looks_disposable(name) then
      if fallback then
        return nil
      end
      fallback = name
    end
  end
  return fallback
end

local function pick_with_cache(root, kind, attr, identity_attr)
  disk_cache[root] = disk_cache[root] or {}
  local cached = disk_cache[root][kind]
  if cached ~= nil then
    return cached
  end
  local picked = nixd_pick(root, attr, identity_attr)
  disk_cache[root][kind] = picked or vim.NIL
  save_disk_cache()
  return picked
end

local function nixd_settings_for_root(root)
  local settings = {
    nixpkgs = {
      expr = string.format('(builtins.getFlake "%s").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}', root),
    },
    formatting = { command = { "nixfmt" } },
    options = {},
  }

  local nixos = pick_with_cache(root, "nixos", "nixosConfigurations", "config.networking.hostName")
  if nixos and nixos ~= vim.NIL then
    settings.options.nixos = {
      expr = string.format('(builtins.getFlake "%s").nixosConfigurations."%s".options', root, nixos),
    }
  end

  local hm = pick_with_cache(root, "hm", "homeConfigurations", "config.home.username")
  if hm and hm ~= vim.NIL then
    settings.options.home_manager = {
      expr = string.format('(builtins.getFlake "%s").homeConfigurations."%s".options', root, hm),
    }
  end

  return settings
end

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
    before_init = function(params, config)
      local root
      if params.workspaceFolders and params.workspaceFolders[1] then
        root = vim.uri_to_fname(params.workspaceFolders[1].uri)
      elseif params.rootUri then
        root = vim.uri_to_fname(params.rootUri)
      end
      if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then
        return
      end
      -- Mutate config.settings in place: vim.lsp.Client captures a reference at
      -- create() time, so reassigning the table here would be ignored.
      config.settings = config.settings or {}
      config.settings.nixd = vim.tbl_deep_extend("force", config.settings.nixd or {}, nixd_settings_for_root(root))
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
  html = {
    cmd = { "vscode-html-language-server", "--stdio" },
    filetypes = { "html", "htm", "templ", "tmpl", "php", "blade", "twig" },
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

  -- Python
  basedpyright = {
    cmd = { "basedpyright-langserver", "--stdio" },
    filetypes = { "python" },
    root_markers = { "pyproject.toml", "setup.py", "requirements.txt", ".git" },
    settings = {
      basedpyright = {
        analysis = { typeCheckingMode = "standard", diagnosticMode = "openFilesOnly" },
      },
    },
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
  dockerls = {
    cmd = { "docker-langserver", "--stdio" },
    filetypes = { "dockerfile" },
    root_markers = { "Dockerfile", ".git" },
  },
  docker_compose_language_service = {
    cmd = { "docker-compose-langserver", "--stdio" },
    filetypes = { "yaml.docker-compose" },
    root_markers = { "docker-compose.yaml", "docker-compose.yml", "compose.yaml", "compose.yml" },
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

    map("n", "grn", vim.lsp.buf.rename, "Rename symbol")
    map({ "n", "x" }, "gra", vim.lsp.buf.code_action, "Code action")
    map("n", "grr", vim.lsp.buf.references, "References")
    map("n", "gri", vim.lsp.buf.implementation, "Implementations")
    map("n", "grd", vim.lsp.buf.definition, "Go to definition")
    map("n", "grt", vim.lsp.buf.type_definition, "Go to type definition")
    map("n", "gO", vim.lsp.buf.document_symbol, "Document symbols")
    map("n", "K", function()
      vim.lsp.buf.hover({ border = "rounded" })
    end, "Hover")

    -- Inlay hints off by default: they reflow the line as you type.
    -- <leader>uh toggles them per buffer.
    vim.lsp.inlay_hint.enable(false, { bufnr = buf })
    map("n", "<leader>uh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
    end, "Toggle inlay hints")

    -- Highlight the symbol under the cursor. This is what vim-illuminate did,
    -- except it's a built-in LSP request and costs nothing when idle.
    local client = vim.lsp.get_client_by_id(args.data.client_id)
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
