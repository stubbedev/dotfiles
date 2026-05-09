{ pkgs, ... }:
let
  laravelNvim = pkgs.vimUtils.buildVimPlugin {
    pname = "laravel.nvim";
    version = "unstable-2026-04";
    src = pkgs.fetchFromGitHub {
      owner = "adalessa";
      repo = "laravel.nvim";
      rev = "387287147a5993517e3a766176b38aa7207d5408";
      hash = "sha256-mTgDFlC8ZWV7lcOaogJToioYlpAbAIv9jHatNcsPzdo=";
    };
    doCheck = false;
    nvimSkipModule = [
      "laravel.api.docker"
      "laravel.api.tinker"
      "laravel.api.app"
      "laravel.utils.log"
      "laravel.utils.fs"
      "laravel.commands.routes"
      "laravel.commands.gf"
      "laravel.commands.related"
      "laravel.commands.open_logs"
      "laravel.commands.user_commands"
      "laravel.commands.open_config_file"
      "laravel.commands.composer"
      "laravel.commands.resources"
      "laravel.commands.configure"
      "laravel.commands.view_finder"
      "laravel.commands.make"
      "laravel.commands.artisan"
      "laravel.commands.flush_cache"
      "laravel.core.watcher"
      "laravel.core.env"
    ];
  };
in
{
  plugins.rustaceanvim.enable = true;
  plugins.crates.enable = true;
  plugins.venv-selector.enable = true;
  plugins.schemastore = {
    enable = true;
    json.enable = true;
    yaml.enable = true;
  };
  plugins.vim-dadbod-completion.enable = true;

  extraPlugins = with pkgs.vimPlugins; [
    go-nvim
    guihua-lua
    templ-vim
    vim-dadbod
    vim-dadbod-ui
    laravelNvim
    promise-async
    nui-nvim
    plenary-nvim
    vim-dotenv
  ];

  keymaps = [
    {
      mode = "n";
      key = "<leader>pa";
      action = ":Laravel artisan<cr>";
      options.desc = "Laravel Artisan";
    }
    {
      mode = "n";
      key = "<leader>pr";
      action = ":Laravel routes<cr>";
      options.desc = "Laravel routes";
    }
    {
      mode = "n";
      key = "<leader>pm";
      action = ":Laravel related<cr>";
      options.desc = "Laravel related";
    }
  ];

  extraConfigLuaPost = ''
    -- go.nvim setup with autoformat on save
    require("go").setup({})
    do
      local go_grp = vim.api.nvim_create_augroup("GoFormat", {})
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.go",
        callback = function() require("go.format").goimports() end,
        group = go_grp,
      })
    end

    -- laravel.nvim — only when in a Laravel project
    if vim.fn.filereadable("artisan") == 1 then
      require("laravel").setup({
        lsp_server = "intelephense",
        features = { null_ls = { enable = false } },
        pickers = { enable = true, provider = "snacks" },
      })
    end
  '';
}
