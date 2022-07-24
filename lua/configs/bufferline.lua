vim.opt.termguicolors = true
require("bufferline").setup{
  options = {
    offsets = {
      { filetype = "netrw", text = "", padding = 1 },
    },
  },
}
