return {
  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    opts = {
        disable_filetype = { "TelescopePrompt" , "vim" },
    } -- this is equalent to setup({}) function
  }
}

