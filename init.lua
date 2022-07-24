require("plugins")

-- netrw file explorer
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3 -- tree style listing
-- vim.g.netrw_browse_split = 4
vim.g.netrw_preview = 1
vim.g.netrw_altv = 1
vim.g.netrw_winsize = 25

-- opt
vim.opt.cursorline = true
vim.opt.fillchars = { eob = " " } -- Disable `~` on nonexistent lines

-- key bindings
vim.g.mapleader = " "
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

vim.keymap.set("n", "<leader>o", function()
  print("test")
  -- todo
end, { desc = "Focus File explorer" })

