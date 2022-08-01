local colors = require 'colors'

-- vim.g.tokyonight_colors = { hint = "orange" }
vim.g.tokyonight_style = 'night'
vim.cmd [[colorscheme tokyonight]]
vim.cmd('highlight VertSplit guibg=' .. colors.black .. ' guifg=White')
