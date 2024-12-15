return {
  {
    "nvim-telescope/telescope.nvim",
    config = function()
      require("telescope").setup({
        pickers = {
          find_files = {
            on_complete = {
              function()
                vim.schedule(function()
                  local action_state = require("telescope.actions.state")
                  local prompt_bufnr = require("telescope.state").get_existing_prompt_bufnrs()[1]

                  local picker = action_state.get_current_picker(prompt_bufnr)
                  if picker == nil then
                    return
                  end
                  local results = picker.layout.results
                  local bufnr = results.bufnr
                  local count = vim.api.nvim_buf_line_count(bufnr)
                  if count == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == "" then
                    local line = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, -1, false)[1]
                    local new_line = line:gsub("'", " ")
                    vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, { new_line })
                  end
                end)
              end,
            },
            default_text = "'",
          },
        },
      })
    end,
  },
}
