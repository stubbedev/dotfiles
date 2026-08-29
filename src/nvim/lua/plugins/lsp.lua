-- nixd attaches per-flake. We feed it `nixosConfigurations.<host>.options`
-- and `homeConfigurations.<user>.options` so completion can index into the
-- right host/user. Discovering the right names requires `nix eval`, which
-- takes 2-3s on a cold flake — enough to visibly hang the first .nix file
-- of the day. Cache the picked names to ~/.cache/nvim/nixd-roots.json,
-- keyed by flake root, so only the very first open per repo pays the cost.

local cache_path = vim.fn.stdpath("cache") .. "/nixd-roots.json"
local nixd_eval_cache = {}

local function load_disk_cache()
  if vim.fn.filereadable(cache_path) == 0 then return {} end
  local lines = vim.fn.readfile(cache_path)
  if not lines or #lines == 0 then return {} end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  return (ok and type(data) == "table") and data or {}
end

local function save_disk_cache(cache)
  local ok, encoded = pcall(vim.json.encode, cache)
  if not ok then return end
  vim.fn.mkdir(vim.fn.fnamemodify(cache_path, ":h"), "p")
  vim.fn.writefile({ encoded }, cache_path)
end

local disk_cache = load_disk_cache()

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
    if ok then result = parsed end
  end
  nixd_eval_cache[key] = result
  return result
end

local function nixd_pick(root, attr, identity_attr)
  local names = nixd_eval(root, attr, "builtins.attrNames")
  if type(names) ~= "table" or #names == 0 then return nil end

  local map = nixd_eval(root, attr, "cs: builtins.mapAttrs (_: c: c." .. identity_attr .. ") cs")
  if type(map) == "table" then
    local hostname = vim.uv.os_gethostname()
    local user = vim.env.USER or ""
    for _, want in ipairs({ hostname, user .. "@" .. hostname, user }) do
      for name, ident in pairs(map) do
        if ident == want then return name end
      end
    end
  end

  local function looks_disposable(name)
    return name:match("[Ii]nstaller") or name:match("[Ii]so") or name:match("[Ll]ive")
  end
  local fallback
  for _, name in ipairs(names) do
    if not looks_disposable(name) then
      if fallback then return nil end
      fallback = name
    end
  end
  return fallback
end

local function pick_with_cache(root, kind, attr, identity_attr)
  disk_cache[root] = disk_cache[root] or {}
  local cached = disk_cache[root][kind]
  if cached ~= nil then return cached end
  local picked = nixd_pick(root, attr, identity_attr)
  disk_cache[root][kind] = picked or vim.NIL
  save_disk_cache(disk_cache)
  return picked
end

local function nixd_settings_for_root(root)
  local settings = {
    nixpkgs = {
      expr = string.format(
        '(builtins.getFlake "%s").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}',
        root
      ),
    },
    formatting = { command = { "nixfmt" } },
    options = {},
  }

  local nixos = pick_with_cache(root, "nixos", "nixosConfigurations", "config.networking.hostName")
  if nixos and nixos ~= vim.NIL then
    settings.options.nixos = {
      expr = string.format(
        '(builtins.getFlake "%s").nixosConfigurations."%s".options',
        root, nixos
      ),
    }
  end

  local hm = pick_with_cache(root, "hm", "homeConfigurations", "config.home.username")
  if hm and hm ~= vim.NIL then
    settings.options.home_manager = {
      expr = string.format(
        '(builtins.getFlake "%s").homeConfigurations."%s".options',
        root, hm
      ),
    }
  end

  return settings
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      -- Language servers outlive nvim whenever it dies without a clean :qa --
      -- a closed terminal, a killed tmux pane, SIGTERM, a crash. nvim only
      -- sends the LSP shutdown/exit handshake on a clean exit, and servers are
      -- supposed to watch the `processId` they get in initialize and quit when
      -- it disappears. phpantom_lsp doesn't, and it idles at ~850MB RSS, so
      -- every unclean exit in a PHP repo leaks that much until reboot.
      --
      -- setpriv(1) sets PR_SET_PDEATHSIG on the server before exec, so the
      -- kernel signals it the moment nvim's process dies -- no cooperation
      -- from the server, and it still fires when nvim is SIGKILLed. Patch
      -- vim.lsp.rpc.start rather than each `cmd`: client.lua derives a
      -- server's default name from cmd[1], which would become "setpriv".
      if vim.fn.has("linux") == 1 and vim.fn.executable("setpriv") == 1 then
        local rpc_start = vim.lsp.rpc.start
        vim.lsp.rpc.start = function(cmd, dispatchers, extra)
          if type(cmd) == "table" and cmd[1] ~= "setpriv" then
            cmd = vim.list_extend({ "setpriv", "--pdeathsig=TERM", "--" }, vim.deepcopy(cmd))
          end
          return rpc_start(cmd, dispatchers, extra)
        end
      end
    end,
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        -- htmx-lsp binary is not installed; disable to suppress exit-code-127 warnings
        htmx = { enabled = false },
        -- nil_ls comes from lazyvim's nix extra; disable so only nixd attaches
        nil_ls = { enabled = false },
        nixd = {
          mason = false,
          settings = {
            nixd = {
              formatting = { command = { "nixfmt" } },
              nixpkgs = { expr = "import <nixpkgs> { }" },
              -- `with` shadows free vars in nested scopes; nixd warns
              -- aggressively, drowning out real diagnostics.
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
            if not root or vim.fn.filereadable(root .. "/flake.nix") == 0 then return end
            -- Mutate config.settings in place: vim.lsp.Client captures a reference at
            -- create() time, so reassigning the table here would be ignored.
            config.settings = config.settings or {}
            config.settings.nixd = vim.tbl_deep_extend(
              "force",
              config.settings.nixd or {},
              nixd_settings_for_root(root)
            )
          end,
        },
        -- css/scss had no language server at all: LazyVim ships no css extra,
        -- so oxfmt (format-only) and nothing else attached. cssls comes from
        -- the vscode-langservers-extracted already in modules/nvim.nix and
        -- brings diagnostics, completion and go-to-definition to both.
        cssls = {},
        oxlint = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
            "svelte",
            "astro",
          },
        },
        oxfmt = {
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
        },
        lua_ls = {
          settings = {
            Lua = {
              runtime = {
                version = "LuaJIT"
              },
              diagnostics = {
                globals = { "vim" }
              },
              workspace = {
                checkThirdParty = false,
                library = {
                  vim.env.VIMRUNTIME,
                  "${3rd}/luv/library",
                  "${3rd}/busted/library",
                  vim.env.VIMRUNTIME .. "/lua"
                }
              }
            }
          }
        },
        html = {
          filetypes = { "html", "htm", "templ", "tmpl", "php", "blade", "twig" },
        },
        templ = {
          filetypes = { "templ" },
          settings = {
            templ = {
              enable_snippets = true,
            },
          },
        },
        bashls = {
          filetypes = { "sh", "zsh" },
        },
        taplo = {
          filetypes = { "toml" },
        },
        -- phpantom_lsp binary supplied by the nvim wrapper (runtimePkgs),
        -- not mason. lspconfig ships the `phpantom_lsp` config (cmd +
        -- filetypes + root_markers); the server key must match that name.
        phpantom_lsp = {
          mason = false,
        }
      },
    },
  },
}
