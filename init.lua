require("plugins")

-- colorscheme
local colors = require "tokyonight.colors".setup {}
-- print(vim.inspect(colors))
vim.g.tokyonight_style = 'night'
vim.cmd [[colorscheme tokyonight]]
vim.cmd('highlight VertSplit guibg=' .. colors.black .. ' guifg=White')

-- netrw file explorer
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3 -- tree style listing
-- vim.g.netrw_browse_split = 4
vim.g.netrw_preview = 1
vim.g.netrw_altv = 1
vim.g.netrw_winsize = 25

-- opt
vim.opt.cursorline = true
vim.opt.fillchars = {
  eob = " ", -- disable `~` on nonexistent lines
  vert = '│', -- window vertical separator character
}
vim.opt.ignorecase = true -- case insensitive search
vim.opt.number = true -- show line numbers
vim.opt.clipboard = "unnamedplus" -- yank to system clipboard

-- key bindings
vim.g.mapleader = " "
vim.keymap.set("", "<Space>", "<Nop>") -- disable space because leader

vim.keymap.set("i", "<Tab>", "<Esc>")
vim.keymap.set("n", "J", "<C-d>", { desc = "Page down" })
vim.keymap.set("n", "K", "<C-u>", { desc = "Page up" })
vim.keymap.set("n", "s", "<cmd>wa<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>yf", ":let @+ = expand('%')<cr>", { desc = "Copy current buffer filepath" })
vim.keymap.set("n", "<leader>C", ":%bd<cr>", { desc = "Close all buffers" })
vim.keymap.set("n", "<leader>q", ":qa<cr>", { desc = "Quit" })

-- window nav
vim.keymap.set("n", "<leader>w", "<C-w>", { desc = "Easier window nav" })
vim.keymap.set("n", "<leader>e", ":Lex<cr>", { desc = "Toggle File explorer" })

-- buffer nav
vim.keymap.set("n", "t", ":bnext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "T", ":bprev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "<leader>c", "<cmd>bdelete<cr>", { desc = "Close buffer" })

-- telescope
vim.keymap.set("n", "<leader>f", ":Telescope find_files<cr>", { desc = "Find files" })
vim.keymap.set("n", "<leader>g", ":Telescope live_grep<cr>", { desc = "Grep" })
vim.keymap.set("n", "<leader>r", function()
  require("telescope.builtin").lsp_references()
end, { desc = "Search references" })
vim.keymap.set("n", "<leader>d", function()
  require("telescope.builtin").diagnostics()
end, { desc = "Search diagnostics" })

-- nvim-tree
vim.keymap.set("n", "<leader>e", ":NvimTreeFocus<cr>", { desc = "Focus file tree" })

-- lsp see lua/configs/lsp.lua
