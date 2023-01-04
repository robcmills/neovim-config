local bg = '#0d1116'

require('tokyonight').setup({
  style = 'night',
  on_colors = function(colors)
    colors.bg = bg
  end
})

vim.cmd[[colorscheme tokyonight]]
vim.cmd('highlight VertSplit guibg=' .. bg .. ' guifg=White')
