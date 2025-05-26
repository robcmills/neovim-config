vim.opt.termguicolors = true
require'bufferline'.setup{
  options = {
    diagnostics = 'nvim_lsp',

    --- count is an integer representing total count of errors
    --- level is a string "error" | "warning"
    --- diagnostics_dict is a dictionary from error level ("error", "warning" or "info")to number of errors for each level.
    --- this should return a string
    --- Don't get too fancy as this function will be executed a lot
    -- diagnostics_indicator = function(count, level, diagnostics_dict, context)
    diagnostics_indicator = function(_, _, diagnostics_dict)
      local s = ""
      for e in pairs(diagnostics_dict) do
        local sym = e == "error" and "" or ""
        s = s .. sym
      end
      return s
    end,

    indicator = {
      icon = '┃ ',
      style = 'icon',
    },
    max_name_length = 50,
    offsets = {
      { filetype = 'netrw', text = '', padding = 0 },
      { filetype = 'NvimTree', text = '', padding = 0 },
    },
    show_buffer_icons = false,
    tab_size = 1,
  },
}
