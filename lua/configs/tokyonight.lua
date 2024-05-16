local bg = '#0d1116'
local white9 = '#e6e6e6' -- 90% luminosity

require('tokyonight').setup({
  style = 'night',
  on_colors = function(colors)
    colors.bg = bg
    colors.comment = '#727ca7' -- lighter gray
    colors.border = white9
  end
})

vim.cmd[[colorscheme tokyonight]]
-- vim.cmd('highlight VertSplit guibg=' .. bg .. ' guifg=White')
