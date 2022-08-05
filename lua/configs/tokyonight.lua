-- local colors = require 'colors'

local bg = '#0d1116'
vim.g.tokyonight_colors = { bg = bg }
vim.g.tokyonight_style = 'night'
vim.cmd [[colorscheme tokyonight]]
vim.cmd('highlight VertSplit guibg=' .. bg .. ' guifg=White')
