-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

require 'plugins'
require 'configs.tokyonight'
require 'colemak'

local function vim_opt_toggle(opt, on, off, name)
  local message = name
  if vim.opt[opt]:get() == off then
    vim.opt[opt] = on
    message = message .. " Enabled"
  else
    vim.opt[opt] = off
    message = message .. " Disabled"
  end
  vim.notify(message)
end

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
vim.opt.signcolumn = 'yes:1'
vim.opt.laststatus = 3 -- makes status line span full screen

-- wrap text and don't break words
vim.opt.wrap = true
vim.opt.linebreak = true
-- indent
vim.opt.shiftwidth = 2 -- Number of space inserted for indentation
vim.opt.autoindent = true
vim.opt.copyindent = true -- Copy the previous indentation on autoindenting
vim.opt.preserveindent = true -- Preserve indent structure as much as possible

-- use ripgrep for grepping (because it's faster)
vim.opt.grepprg = "rg --vimgrep --no-heading --smart-case"

-- folding
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99

-- key bindings
vim.g.mapleader = " "
vim.keymap.set("", "<Space>", "<Nop>") -- disable space because leader

vim.keymap.set("i", "<Tab>", "<Esc>")
vim.keymap.set("n", "U", "<C-r>", { desc = "Redo" })
vim.keymap.set("n", "J", "gJi <ESC>ciW <ESC>", { desc = "Join lines (and remove excess whitespace)" })
vim.keymap.set("n", "s", "<cmd>wa<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>yf", ":let @+ = expand('%')<cr>", { desc = "Copy current buffer filepath" })
vim.keymap.set("n", "<leader>q", ":qa<cr>", { desc = "Quit" })
vim.keymap.set("n", "<leader>h", "<cmd>nohlsearch<cr>", { desc = "No Highlight" })
vim.keymap.set("n", "<leader>A", "gg0vG$y", { desc = "Copy all" })
vim.keymap.set("n", "<leader>'", "ciw''<ESC>P", { desc = "Surround word with single quotes" })
vim.keymap.set("n", '<leader>"', 'ciw""<ESC>P', { desc = "Surround word with double quotes" })

-- window nav
vim.keymap.set("n", "<leader>w", "<C-w>", { desc = "Easier window nav" })
vim.keymap.set("n", "<leader>e", ":Lex<cr>", { desc = "Toggle File explorer" })

-- buffer nav
vim.keymap.set("n", "t", ":BufferLineCycleNext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "T", ":BufferLineCyclePrev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "<leader><", ":BufferLineMovePrev<cr>", { desc = "Move buffer left" })
vim.keymap.set("n", "<leader>>", ":BufferLineMoveNext<cr>", { desc = "Move buffer right" })
vim.keymap.set("n", "<leader>C", ":%bd<cr>", { desc = "Close all buffers" })

-- indent
vim.keymap.set("v", "<", "<gv", { desc = "Decrease indent without losing selection" })
vim.keymap.set("v", ">", ">gv", { desc = "Increase indent without losing selection" })

vim.keymap.set("n", "<leader>c", function()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.cmd('bp')
  vim.api.nvim_buf_delete(bufnr, { force = true })
end, { desc = "Close buffer" })

vim.keymap.set("n", "<leader>n", function()
  local filename = vim.fn.input('Filename: ')
  if filename then
    vim.cmd(':e %:h/' .. filename)
    vim.cmd(':w')
  end
end, { desc = "New buffer" })


-- telescope
vim.keymap.set("n", "<leader>f", ":Telescope find_files<cr>", { desc = "Find files" })
vim.keymap.set("n", "<leader>g", ":Telescope live_grep<cr>", { desc = "Grep" })
vim.keymap.set("n", "<leader>r", function()
  require("telescope.builtin").lsp_references()
end, { desc = "Search references" })
vim.keymap.set("n", "<leader>d", function()
  require("telescope.builtin").diagnostics()
end, { desc = "Search diagnostics" })
vim.keymap.set("n", "<leader>b", function()
  require("telescope.builtin").buffers()
end, { desc = "Search buffers" })
vim.keymap.set("n", "<leader>p", function()
  require("telescope.builtin").help_tags()
end, { desc = "Search help" })
vim.keymap.set("n", "<leader>m", ":Telescope symbols<cr>", { desc = "Symbols" })

-- nvim-tree
vim.keymap.set("n", "<leader>e", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  if filetype == 'NvimTree' then
    vim.cmd('wincmd l')
  else
    vim.cmd('NvimTreeFocus')
  end
end, { desc = "Toggle file tree focus" })
vim.keymap.set("n", "<leader>E", ":NvimTreeToggle<cr>", { desc = "Toggle file tree open" })

-- toggle comment
vim.keymap.set("n", "<leader>/", function()
  require("Comment.api").toggle.linewise.current()
end, { desc = "Comment line" })
vim.keymap.set('x', '<leader>/', '<esc><cmd>lua require("Comment.api").toggle.linewise(vim.fn.visualmode())<cr>')

-- eslint
vim.keymap.set("n", "<leader>a", ":EslintFixAll<cr>", { desc = "EslintFixAll" })

-- spell check
vim.keymap.set('n', '<leader>s', function()
  vim.notify('spell')
  vim_opt_toggle('spell', true, false, 'Spell')
end, { desc = 'Toggle spell checking' })
-- vim.cmd('setlocal spell spelllang=en_us')
vim.opt.spelllang = 'en_us'
-- Show nine spell checking candidates at most
vim.opt.spellsuggest = 'best,9'


-- lsp see lua/configs/lsp.lua

-- vim.api.nvim_create_autocmd('BufReadPost', { pattern = '*.overlay', command = 'set syntax=c'})

local function conflicts()
  local command = 'git diff --name-only --diff-filter=U'
  local list = vim.fn.system(command)

  if list ~= '' then
    local files = vim.split(list, '\n')
    for _, file in pairs(files) do
      vim.api.nvim_command('edit ' .. string.gsub(file, "web/icedemon/", ""))
    end
  else
    vim.api.nvim_err_write("No Git merge conflicts found.\n")
  end
end

vim.keymap.set('n', '<leader>x', function()
  conflicts()
end, { desc = 'Open all files with git merge conflicts' })

