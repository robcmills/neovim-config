vim.opt.termguicolors = true
require'bufferline'.setup{
  options = {
    offsets = {
      { filetype = 'netrw', text = '', padding = 1 },
    },
    max_name_length = 20,
    tab_size = 25,
  },
}
