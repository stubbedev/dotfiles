
local M = {}

local cache_path = vim.fn.stdpath("cache") .. "/nixd-roots.json"

local function load_cache()
  if vim.fn.filereadable(cache_path) == 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(cache_path), "\n"))
  return (ok and type(data) == "table") and data or {}
end

local cache = load_cache()

local function save_cache()
  local ok, encoded = pcall(vim.json.encode, cache)
  if not ok then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(cache_path, ":h"), "p")
  vim.fn.writefile({ encoded }, cache_path)
end

local function flake_expr(root, attr)
  return { expr = string.format('(builtins.getFlake "%s").%s', root, attr) }
end

function M.settings(root)
  local entry = type(cache[root]) == "table" and cache[root] or {}
  local options = {}
  if type(entry.nixos) == "string" then
    options.nixos = flake_expr(root, ('nixosConfigurations."%s".options'):format(entry.nixos))
  end
  if type(entry.hm) == "string" then
    options.home_manager = flake_expr(root, ('homeConfigurations."%s".options'):format(entry.hm))
  end
  return {
    nixpkgs = flake_expr(root, "inputs.nixpkgs.legacyPackages.${builtins.currentSystem}"),
    formatting = { command = { "nixfmt" } },
    options = options,
  }
end

local function eval(root, attr, apply, cb)
  local cmd = { "nix", "eval", "--json", "--no-warn-dirty", root .. "#" .. attr }
  if apply then
    vim.list_extend(cmd, { "--apply", apply })
  end
  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(res)
      local ok, parsed = pcall(vim.json.decode, res.stdout)
      cb(res.code == 0 and ok and parsed or nil)
    end)
  )
end

local function pick(names, map)
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

  local fallback
  for _, name in ipairs(names) do
    if not name:match("[Ii]nstaller") and not name:match("[Ii]so") and not name:match("[Ll]ive") then
      if fallback then
        return nil
      end
      fallback = name
    end
  end
  return fallback
end

local function pick_async(root, attr, identity, cb)
  eval(root, attr, "builtins.attrNames", function(names)
    if type(names) ~= "table" or #names == 0 then
      return cb(nil)
    end
    eval(root, attr, ("cs: builtins.mapAttrs (_: c: c.%s) cs"):format(identity), function(map)
      cb(pick(names, map))
    end)
  end)
end

local warming = {}

function M.warm(root, client)
  if warming[root] or cache[root] then
    return
  end
  warming[root] = true

  local pending, entry = 2, {}
  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    cache[root] = entry
    save_cache()
    if client:is_stopped() then
      return
    end
    local settings = vim.tbl_deep_extend("force", client.settings or {}, { nixd = M.settings(root) })
    client.settings = settings
    client:notify("workspace/didChangeConfiguration", { settings = settings })
  end

  pick_async(root, "nixosConfigurations", "config.networking.hostName", function(name)
    entry.nixos = name or false
    done()
  end)
  pick_async(root, "homeConfigurations", "config.home.username", function(name)
    entry.hm = name or false
    done()
  end)
end

return M
