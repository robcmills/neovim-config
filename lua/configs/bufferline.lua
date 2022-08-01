vim.opt.termguicolors = true
require'bufferline'.setup{
  options = {
    indicator_icon = '┃ ',
    max_name_length = 50,
    offsets = {
      { filetype = 'netrw', text = '', padding = 0 },
      { filetype = 'NvimTree', text = '', padding = 0 },
    },
    show_buffer_icons = false,
    tab_size = 1,
  },
}
