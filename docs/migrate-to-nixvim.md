# Migrate Neovim config from LazyVim → nixvim

## Context

Today the user's Neovim config lives in `src/nvim/` as a stock LazyVim setup (lazy.nvim + Mason + 17 LazyVim "extras" + ~30 custom plugin specs + custom Blade treesitter queries) and is wired into the home via a live symlink (`modules/activation/_non-privileged/setup-nvim.nix`: `~/.stubbe/src/nvim` → `~/.config/nvim`). Mason auto-installs Vue/SCSS LSPs outside Nix, and `lua/plugins/lsp.lua` hard-codes `~/.bun/bin/prettier`. These are leaks: not every editor dependency is reproducible from the flake.

**Goal:** every plugin, LSP, formatter, parser, and treesitter query pinned by Nix. Drop LazyVim and lazy.nvim entirely; declare the editor through `programs.nixvim`. The user has accepted the DX change (rebuild on every config tweak) and wants a full rewrite, not a hybrid.

**Constraint (from saved feedback):** any `flake.modules.homeManager.*` module must build cleanly on BOTH `homeConfigurations.stubbe` (standalone HM) and `nixosConfigurations.stubbe-nixos` (NixOS+HM bridge). Verify both targets at every phase.

**Strategy:** stand up nixvim alongside the existing LazyVim setup as a separate `nvim-new` binary (via `NVIM_APPNAME=nvim-new` and the `inputs.nixvim.legacyPackages.<sys>.makeNixvimWithModule` evaluator). Reach feature parity, then in one cutover commit flip to `programs.nixvim.enable = true`, delete the activation symlink, repoint EDITOR/VISUAL/git, and remove the bare `pkgs.neovim` from `home.packages`. The current `nvim` keeps working unchanged until the cutover.

## Module layout

`programs.nixvim` is one big attrset that HM merges across modules — split for legibility, not capability. New tree under `modules/programs/nvim/`:

| File | Responsibility |
|---|---|
| `default.nix` | top-level: `programs.nixvim.{enable,colorschemes,opts,globals,keymaps,autoCmd}`, the `extraConfigLua` for hover handler / filetype / TS language register, gated on `config.features.desktop` |
| `lsp.nix` | `plugins.lspconfig.servers.*` for nixd, lua_ls, html, templ, bashls, taplo, tsserver, oxlint, oxfmt, intelephense, volar, somesass_ls, tailwindcss |
| `formatters.nix` | `plugins.conform-nvim` wired to nixpkgs prettier/oxfmt/pint/caddy/stylua (+ `extraFiles."stylua.toml"`) |
| `plugins-treesitter.nix` | `plugins.treesitter` w/ explicit grammar list, `treesitter-context`, `treesitter-textobjects`, `nvim-ts-autotag`; `extraFiles` for the four `after/queries/*.scm` files |
| `plugins-core.nix` | snacks (terminal/explorer/scroll/indent/dashboard-default OFF; STUBBE header), lualine, noice, edgy, which-key, oil(+git-status), gitsigns, todo-comments, trouble, persistence, mini.{ai,pairs,surround,hipatterns,icons}, web-devicons, notify, render-markdown, markdown-preview, vim-illuminate, ts-comments |
| `plugins-completion.nix` | blink-cmp, blink-copilot, friendly-snippets, lazydev |
| `dap.nix` | nvim-dap, dap-ui, dap-virtual-text, dap-go, dap-python, one-small-step-for-vimkind |
| `test.nix` | neotest + python/phpunit/golang adapters, overseer |
| `ai.nix` | copilot.lua, sudo-tee/opencode.nvim |
| `lang-go.nix` / `lang-php.nix` / `lang-rust.nix` / `lang-python.nix` / `lang-vue.nix` / `lang-web.nix` / `lang-data.nix` | per-language plugins (go.nvim, laravel.nvim, rustaceanvim+crates, venv-selector, vue extras, schemastore+scss+tailwind+templ, vim-dadbod stack) |
| `utility.nix` | kulala, dooku, cronex, multicursor, undotree, refactoring, dial, inc-rename, grug-far, tmux.nvim, nvim-recorder |
| `extra-plugins.nix` | `pkgs.vimUtils.buildVimPlugin` entries for plugins not in `nixpkgs.vimPlugins` (likely: opencode.nvim, blink-copilot, dooku.nvim, cronex.nvim, oil-git-status, neotest-phpunit if missing, possibly multicursor.nvim, possibly nvim-recorder) |
| `queries/` | move `src/nvim/after/queries/*.scm` here so the module is self-contained (referenced via `extraFiles."after/queries/...".source = ./queries/...`) |

Each file uses the existing pattern: `_: { flake.modules.homeManager.programsNvim<Suffix> = { lib, config, pkgs, ... }: lib.mkIf config.features.desktop { programs.nixvim.<...>; }; }`.

## Phased steps

Each phase ends with the dual-target build check:

```
nix build --impure path:.#nixosConfigurations.stubbe-nixos.config.system.build.toplevel
nix build --impure path:.#homeConfigurations.stubbe.activationPackage
home-manager switch --flake path:.   # then exercise nvim-new
```

### Phase 0 — flake input
Edit `flake.nix`. Add:
```nix
nixvim = {
  url = "github:nix-community/nixvim";  # default branch tracks nixos-unstable
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
  inputs.home-manager.follows = "home-manager";
};
```
Verify both builds still work (no consumer yet).

### Phase 1 — skeleton + `nvim-new` wrapper
Create `modules/programs/nvim/default.nix`. Build a standalone package via `inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvimWithModule` and expose it as a `writeShellScriptBin "nvim-new"` setting `NVIM_APPNAME=nvim-new`. Do NOT set `programs.nixvim.enable = true` yet — that would clobber the live symlink.

Port from `src/nvim/lua/config/`:
- `options.lua` → `globals.{mapleader=" ", maplocalleader=" "}`, `globals.autoformat=false`, `globals.lazyvim_php_lsp="intelephense"`, `globals.root_spec=[".git" "lsp" "cwd"]`, `opts.{mouse="", foldlevel=99}`, foldtext via `__raw`, `extraConfigLua` for `vim.treesitter.language.register("html", {"html","tmpl"})` + same for templ + `vim.filetype.add` for caddy + the `textDocument/hover` handler verbatim.
- `keymaps.lua` → nixvim `keymaps` list. Drop `<leader>ll`/`<leader>le` (Lazy commands won't apply). Drop the `<leader>ft`/`<leader>fT` disable (snacks terminal will be off entirely).
- `autocmds.lua` → `autoCmd` entries for `.env*` diagnostics-disable and `LspAttach` inlay-hints-disable, both with `callback.__raw`.

Smoke check: `nvim-new` opens, `:set foldlevel?` returns 99, leader keymaps work. Existing `nvim` (LazyVim) still works untouched.

### Phase 2 — LSP servers
Create `modules/programs/nvim/lsp.nix`. Two passes:

**2a easy 9:** nixd (port the `before_init` flake-eval Lua via `extraOptions.before_init.__raw`), lua_ls (fold `.neoconf.json`'s neodev into `settings.Lua.workspace.library`), html (filetypes incl. php/blade/twig/templ/tmpl), templ, bashls, taplo, tsserver, oxlint, oxfmt.

**2b heavyweight:** intelephense (full ~78-stub array, `files.maxSize=500000000`, environment.includePaths) — port verbatim; volar (`vue.hybridMode=false`, filetypes=[vue]); somesass_ls; tailwindcss (excludes php/blade). Leave htmx and nil_ls disabled (just don't list them).

Each server's package comes from nixpkgs (nixd, lua-language-server, vscode-langservers-extracted, templ, bash-language-server, taplo, typescript-language-server, oxlint, oxfmt, intelephense, vue-language-server, some-sass-language-server, tailwindcss-language-server). Set `package = pkgs.<name>` if nixvim's default doesn't resolve.

Smoke: open a `.nix`/`.lua`/`.php`/`.ts`/`.vue`/`.scss`/`.toml`/`.html`; each attaches the right LSP. In a flake repo, nixd's `nixpkgs.expr` is populated.

### Phase 3 — formatters
Create `modules/programs/nvim/formatters.nix`. Port `lua/plugins/conform.lua`. Crucially: replace the `~/.bun/bin/prettier` path with `lib.getExe pkgs.nodePackages.prettier`. Add `pint` to `modules/packages/development.nix` `home.packages` (caddy/stylua/oxfmt/oxlint/prettier already there). `extraFiles."stylua.toml".text` carries the existing `stylua.toml`.

Smoke: `:ConformInfo` shows `/nix/store/...` paths, no `~/.bun/...`.

### Phase 4 — treesitter + queries
Create `modules/programs/nvim/plugins-treesitter.nix` and `modules/programs/nvim/queries/` (copy from `src/nvim/after/queries/`, but DO NOT delete the originals yet — phase 10 step). Set explicit `grammarPackages` covering: bash, c, caddy, css, scss, dockerfile, go, gomod, gosum, html, javascript, json, jsonc, lua, luadoc, markdown, markdown_inline, nix, php, php_only, blade, python, query, regex, rust, sql, templ, toml, tsx, typescript, vim, vimdoc, vue, yaml. `auto_install = false`.

Wire `extraFiles` for `after/queries/blade/{injections,folds,highlights}.scm` and `after/queries/injections.scm` from `./queries/...`.

Smoke: `:TSInstall` errors (parsers pinned). Open `.blade.php` — highlights, folds work. Open HTML with `x-data` AlpineJS attribute — JS injection highlights.

### Phase 5 — core plugins + completion
Create `plugins-core.nix` and `plugins-completion.nix`. Port `lua/plugins/{snacks,lualine,noice,edgy,oil,oil-git-status.nvim,which-key,colorscheme,blink}.lua` etc. Snacks: `terminal/explorer/scroll/indent.enabled=false`, `dashboard.preset.header` = STUBBE ascii from `disabled.lua`. Add a comment block listing LazyVim defaults that are NOT being enabled: `mini.indentscope, alpha-nvim, flash, akinsho/bufferline`.

Smoke: STUBBE dashboard, which-key, oil, gitsigns column, completion fires.

### Phase 6 — language plugins
Create `lang-go.nix` (ray-x/go.nvim+guihua), `lang-php.nix` (laravel.nvim), `lang-rust.nix` (rustaceanvim, crates-nvim), `lang-python.nix` (venv-selector), `lang-vue.nix` (vue plugin extras; volar already done), `lang-web.nix` (schemastore + scss/tailwind extras + templ.vim), `lang-data.nix` (vim-dadbod + ui + completion).

Smoke: open one file per language; each plugin's commands available.

### Phase 7 — DAP + neotest
Create `dap.nix` and `test.nix`. Likely `neotest-phpunit` and `neotest-golang` need extra-plugins entries; `nvim-dap*`/`one-small-step-for-vimkind` mostly in nixpkgs. `overseer.enable = true`.

Smoke: `:DapShowLog`, `:Neotest summary`, run a Go test.

### Phase 8 — AI
Create `ai.nix` + add to `extra-plugins.nix`. `copilot-lua.enable = true`. `sudo-tee/opencode.nvim` and `blink-copilot` via `pkgs.vimUtils.buildVimPlugin { src = pkgs.fetchFromGitHub {...}; }`. Port `lua/plugins/opencode.lua` settings into `extraConfigLua`. **First time we exercise extraPlugins** — expect 1–2 hash mismatches; fix iteratively (`nix build` will print the expected hash).

### Phase 9 — utility plugins
Create `utility.nix`. kulala, dooku.nvim, cronex.nvim, jake-stewart/multicursor.nvim, undotree, refactoring.nvim, dial.nvim, inc-rename.nvim, grug-far.nvim, tmux.nvim, nvim-recorder. Several will need `extra-plugins.nix` entries.

Smoke: `:UndotreeToggle`, multicursor mappings, kulala on `.http`, dial increments.

### Phase 10 — cutover (single commit)
This is the only destructive phase. Order matters because the symlink and nixvim's xdg.configFile both target `~/.config/nvim`.

1. Walk a parity checklist in `nvim-new`: every LazyVim extra reproduced, `:checkhealth` clean, every LSP attaches in a representative project.
2. In `modules/programs/nvim/default.nix`: replace the `makeNixvimWithModule` + `nvim-new` wrapper with a direct `programs.nixvim.enable = true;`. The sibling files keep working unchanged (they already write under `programs.nixvim.*`).
3. Delete `modules/activation/_non-privileged/setup-nvim.nix`.
4. `modules/programs/git.nix`: change `core.editor` to `${config.programs.nixvim.finalPackage}/bin/nvim`.
5. `modules/home/session-variables.nix`: change `EDITOR`/`VISUAL` to `lib.getExe config.programs.nixvim.finalPackage`.
6. `modules/packages/development.nix`: drop the bare `neovim` from `home.packages`. Keep `(homeLib.gfx neovide)`, `tree-sitter`, the lua bins, `pint`.
7. Decide on `src/nvim/`: recommend renaming to `src/nvim.lazyvim-archive/` for one cycle, then delete. The `after/queries/` files were already copied to `modules/programs/nvim/queries/` in phase 4. `.neoconf.json` and `stylua.toml` are folded into the nixvim module.

All seven changes go in one commit so the build is consistent.

**Final verification:**
- Both dual-target builds pass.
- `home-manager switch --flake path:.#stubbe` (standalone target) and `sudo nixos-rebuild test --flake path:.#stubbe-nixos` (NixOS target).
- Fresh shell: `which nvim` resolves to the HM profile; `nvim --version` shows nixvim wrapper; `git config --get core.editor` is a `/nix/store/...` path; `echo $EDITOR` likewise.
- Open this very dotfiles repo: nixd flake-aware completion works (proves the `before_init` port is correct). Open a Laravel project: intelephense attaches, conform's pint works. Copilot suggests; opencode keymaps respond.
- Confirm `~/.config/nvim` is now a regular directory written by HM, not a symlink to `~/.stubbe/src/nvim`.

**Rollback:** until phase 10 is committed, `nvim` is unchanged. Each pre-cutover phase is independently revertable. If the cutover commit breaks activation, `git revert` it and switch back.

## Risks specific to this repo

- **Dual targets** (`stubbe` and `stubbe-nixos`) — every phase MUST verify both. The standalone HM target lacks NixOS module merging; if any phase accidentally relies on a NixOS option, only stubbe-nixos will build.
- **`tree-sitter` flake input** — repo pins upstream master because nixpkgs ships 0.25.x and nvim-treesitter requires 0.26.1+. nixvim's treesitter uses `pkgs.tree-sitter` by default. If parser builds fail in phase 4, override `programs.nixvim.plugins.treesitter.package` (or treat parser packages individually) so the pinned `inputs.tree-sitter.packages.${system}.cli` is used at parser-build time.
- **nixd `before_init` shells out to `nix eval`** — works only if `nix` is on the wrapped nvim's runtime PATH. nixvim's default wrapper preserves PATH, but if `wrapRc`/`wrapper` config strips env, the flake-aware settings will silently fall back. Verify in phase 2 by inspecting `vim.lsp.get_clients({name="nixd"})[1].config.settings`.
- **`pkgs.neovim` removal ordering** — only safe in phase 10 because `EDITOR`/`VISUAL`/`git.core.editor` reference it until then. Single commit avoids a window where they reference a removed package.
- **The `setup-nvim.nix` deletion must coincide with `programs.nixvim.enable = true`** — otherwise `~/.config/nvim` collides between the activation symlink and HM's xdg writes, and HM refuses to clobber.
- **`features.desktop` gate** — the existing symlink is gated on it. Every new module must mirror via `lib.mkIf config.features.desktop`. Headless hosts (e.g. installer ISO) currently have no nvim — keep that.
- **Plugin packaging risk** — extra-plugins.nix is the most likely failure surface. Cluster risky plugins (opencode, dooku, cronex, multicursor, nvim-recorder) into late phases (8–9) so unrelated phases can land first.

## Critical files to modify

- `/etc/nixos/dotfiles/flake.nix` — phase 0
- `/etc/nixos/dotfiles/modules/programs/nvim/{default,lsp,formatters,plugins-treesitter,plugins-core,plugins-completion,dap,test,ai,lang-*,utility,extra-plugins}.nix` — phases 1–9 (new tree)
- `/etc/nixos/dotfiles/modules/programs/nvim/queries/*.scm` — phase 4 (copied from `src/nvim/after/queries/`)
- `/etc/nixos/dotfiles/modules/activation/_non-privileged/setup-nvim.nix` — DELETED in phase 10
- `/etc/nixos/dotfiles/modules/programs/git.nix` — phase 10 (`core.editor`)
- `/etc/nixos/dotfiles/modules/home/session-variables.nix` — phase 10 (`EDITOR`, `VISUAL`)
- `/etc/nixos/dotfiles/modules/packages/development.nix` — phase 3 (add `pint`), phase 10 (drop `neovim`)
- `/etc/nixos/dotfiles/src/nvim/` — phase 10 (rename to `src/nvim.lazyvim-archive/` or delete)
