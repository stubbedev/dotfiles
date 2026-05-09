{ pkgs, ... }:
let
  dookuNvim = pkgs.vimUtils.buildVimPlugin {
    pname = "dooku.nvim";
    version = "unstable-2026-04";
    src = pkgs.fetchFromGitHub {
      owner = "Zeioth";
      repo = "dooku.nvim";
      rev = "19ce5a25004ea6291c0968fe9d86793c272af8df";
      hash = "sha256-3509EshJOuybPEY44xjK450L8VcZmfEze8wx6LiBAoI=";
    };
    doCheck = false;
  };

  cronexNvim = pkgs.vimUtils.buildVimPlugin {
    pname = "cronex.nvim";
    version = "unstable-2026-04";
    src = pkgs.fetchFromGitHub {
      owner = "fabridamicelli";
      repo = "cronex.nvim";
      rev = "d1b938bf5a8ef9a8dfa1e63a95b1e82c1c5864ba";
      hash = "sha256-blqm0FXEQl/H843HK2CPmhtndQ+nuG3eGpgb1CC4/bg=";
    };
    doCheck = false;
  };
in
{
  plugins.kulala.enable = true;
  plugins.undotree.enable = true;
  plugins.dial.enable = true;
  plugins.inc-rename.enable = true;
  plugins.grug-far.enable = true;

  extraPlugins = with pkgs.vimPlugins; [
    multicursor-nvim
    refactoring-nvim
    async-nvim
    tmux-nvim
    dookuNvim
    cronexNvim
  ];

  keymaps = [
    {
      mode = "n";
      key = "<leader>z";
      action.__raw = "function() vim.cmd.UndotreeToggle() end";
      options.desc = "Undotree toggle";
    }
    {
      mode = "v";
      key = "<leader>z";
      action.__raw = "function() vim.cmd.UndotreeToggle() end";
      options.desc = "Undotree toggle";
    }
    {
      mode = [ "n" "x" ];
      key = "<up>";
      action.__raw = "function() require('multicursor-nvim').lineAddCursor(-1) end";
      options.desc = "Multicursor: add cursor above";
    }
    {
      mode = [ "n" "x" ];
      key = "<down>";
      action.__raw = "function() require('multicursor-nvim').lineAddCursor(1) end";
      options.desc = "Multicursor: add cursor below";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader><up>";
      action.__raw = "function() require('multicursor-nvim').lineSkipCursor(-1) end";
      options.desc = "Multicursor: skip cursor above";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader><down>";
      action.__raw = "function() require('multicursor-nvim').lineSkipCursor(1) end";
      options.desc = "Multicursor: skip cursor below";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>n";
      action.__raw = "function() require('multicursor-nvim').matchAddCursor(1) end";
      options.desc = "Multicursor: match add cursor forward";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>s";
      action.__raw = "function() require('multicursor-nvim').matchSkipCursor(1) end";
      options.desc = "Multicursor: match skip cursor forward";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>N";
      action.__raw = "function() require('multicursor-nvim').matchAddCursor(-1) end";
      options.desc = "Multicursor: match add cursor backward";
    }
    {
      mode = [ "n" "x" ];
      key = "<leader>S";
      action.__raw = "function() require('multicursor-nvim').matchSkipCursor(-1) end";
      options.desc = "Multicursor: match skip cursor backward";
    }
    {
      mode = "n";
      key = "<c-leftmouse>";
      action.__raw = "function() require('multicursor-nvim').handleMouse() end";
      options.desc = "Multicursor: toggle cursor";
    }
    {
      mode = "n";
      key = "<c-leftdrag>";
      action.__raw = "function() require('multicursor-nvim').handleMouseDrag() end";
      options.desc = "Multicursor: drag cursors";
    }
    {
      mode = "n";
      key = "<c-leftrelease>";
      action.__raw = "function() require('multicursor-nvim').handleMouseRelease() end";
      options.desc = "Multicursor: release drag";
    }
    {
      mode = [ "n" "x" ];
      key = "ga";
      action.__raw = "function() require('multicursor-nvim').addCursorOperator() end";
      options.desc = "Multicursor: add cursor for each line in motion";
    }
  ];

  extraConfigLuaPost = ''
    -- multicursor.nvim setup + layered keymaps + highlights
    do
      local mc = require("multicursor-nvim")
      mc.setup()

      mc.addKeymapLayer(function(layerSet)
        layerSet({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Multicursor: previous cursor" })
        layerSet({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Multicursor: next cursor" })
        layerSet({ "n", "x" }, "<leader>x", mc.deleteCursor, { desc = "Multicursor: delete cursor" })
        layerSet("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end, { desc = "Multicursor: enable or clear cursors" })
      end)

      local hl = vim.api.nvim_set_hl
      hl(0, "MultiCursorCursor", { reverse = true })
      hl(0, "MultiCursorVisual", { link = "Visual" })
      hl(0, "MultiCursorSign", { link = "SignColumn" })
      hl(0, "MultiCursorMatchPreview", { link = "Search" })
      hl(0, "MultiCursorDisabledCursor", { reverse = true })
      hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
      hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
    end

    -- tmux.nvim setup
    pcall(function() require("tmux").setup({}) end)

    -- dooku.nvim
    require("dooku").setup({
      project_root = { ".git", ".hg", ".svn", ".bzr", "_darcs", "_FOSSIL_", ".fslckout" },
      browser_cmd = "xdg-open",
      on_bufwrite_generate = false,
      on_generate_open = true,
      auto_setup = true,
      on_generate_notification = true,
      on_open_notification = true,
    })

    -- cronex.nvim
    require("cronex").setup({})
  '';
}
