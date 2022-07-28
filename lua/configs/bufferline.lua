vim.opt.termguicolors = true
require'bufferline'.setup{
  options = {
    indicator_icon = '│',
    max_name_length = 25,
    offsets = {
      { filetype = 'netrw', text = '', padding = 0 },
      { filetype = 'NvimTree', text = '', padding = 0 },
    },
    tab_size = 1,
  },
}
