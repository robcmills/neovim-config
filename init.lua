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
  vertright = '─',
}
vim.opt.ignorecase = true -- case insensitive search
vim.opt.number = true -- show line numbers
vim.opt.clipboard = "unnamedplus" -- yank to system clipboard
vim.opt.signcolumn = 'yes:1'
vim.opt.laststatus = 3 -- makes status line span full screen
vim.opt.colorcolumn = "80,120" -- line length marker

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

vim.opt.directory = vim.fn.expand('$HOME/.local/state/nvim/swap//')

-- key bindings
vim.g.mapleader = " "
vim.keymap.set("", "<Space>", "<Nop>") -- disable space because leader

vim.keymap.set("i", "<Tab>", "<Esc>")
vim.keymap.set("n", "U", "<C-r>", { desc = "Redo" })
vim.keymap.set("n", "<C-j>", "gJi <ESC>ciW <ESC>", { desc = "Join lines (and remove excess whitespace)" })
vim.keymap.set("n", "s", "<cmd>wa<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>yf", ":let @+ = expand('%')<cr>", { desc = "Copy current buffer filepath" })
vim.keymap.set("n", "<leader>q", ":qa<cr>", { desc = "Quit all" })
vim.keymap.set("n", "<C-q>", ":q<cr>", { desc = "Quit" })
vim.keymap.set("n", "<leader>h", ":nohlsearch<cr>", { desc = "No Highlight" })
vim.keymap.set("n", "<leader>A", "gg0vG$y", { desc = "Copy all" })
vim.keymap.set("n", "<leader>'", "ciw''<ESC>P", { desc = "Surround word with single quotes" })
vim.keymap.set("n", '<leader>"', 'ciw""<ESC>P', { desc = "Surround word with double quotes" })
vim.keymap.set("n", '<leader>(', 'ciw()<ESC>P', { desc = "Surround word with parens" })
vim.keymap.set("n", '<leader>{', 'ciw{}<ESC>P', { desc = "Surround word with curly brackets" })

-- terminal
vim.opt.scrollback = 50000
vim.o.shell = "bash -l" -- use "login" bash to source .bash_profile
-- vim.o.shell = "/Applications/fish.app/Contents/Resources/base/usr/local/bin/fish"
vim.keymap.set('n', '<leader>t', function()
  vim.cmd('term')
  vim.wait(1)
  vim.cmd('startinsert')
end, { desc = 'Terminal' })
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit insert mode in terminal' })
vim.keymap.set('t', '<C-k>', function()
  vim.fn.feedkeys("", 'n')
  local sb = vim.bo.scrollback
  vim.bo.scrollback = 1
  vim.bo.scrollback = sb
end, { desc = 'Clear terminal' })
vim.cmd [[
  augroup terminal
    autocmd!
    autocmd TermOpen * setlocal nonumber norelativenumber
  augroup END
]]

-- window nav
vim.keymap.set("n", "<leader>w", "<C-w>w", { desc = "Move to next window", noremap = true })
vim.keymap.set("n", "<leader>W", "<C-w>W", { desc = "Move to prev window", noremap = true })
vim.keymap.set("n", "<leader>e", ":Lex<cr>", { desc = "Toggle File explorer" })

-- buffer nav
vim.keymap.set("n", "t", ":BufferLineCycleNext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "T", ":BufferLineCyclePrev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "<leader><", ":BufferLineMovePrev<cr>", { desc = "Move buffer left" })
vim.keymap.set("n", "<leader>>", ":BufferLineMoveNext<cr>", { desc = "Move buffer right" })
vim.keymap.set("n", "<leader>C", ":%bd | NvimTreeFocus | NvimTreeCollapse | NvimTreeRefresh<cr>gg", { desc = "Close all buffers" })
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

-- indent
vim.keymap.set("v", "<", "<gv", { desc = "Decrease indent without losing selection" })
vim.keymap.set("v", ">", ">gv", { desc = "Increase indent without losing selection" })

-- telescope
vim.keymap.set("n", "<leader>f", function()
  require("telescope.builtin").find_files()
end, { desc = "Find files" })
vim.keymap.set("n", "<leader>p", function()
  require("telescope.builtin").live_grep()
end, { desc = "Grep" })
vim.keymap.set("n", "<leader>r", function()
  require("telescope.builtin").lsp_references()
end, { desc = "Search references" })
vim.keymap.set("n", "<leader>d", function()
  require("telescope.builtin").diagnostics()
end, { desc = "Search diagnostics" })
vim.keymap.set("n", "<leader>b", function()
  require("telescope.builtin").buffers()
end, { desc = "Search buffers" })
vim.keymap.set("n", "<leader>m", function()
  require("telescope.builtin").symbols()
end, { desc = "Symbols" })


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

function set_unique_buffer_name(bufnr, base_name)
  local count = 1
  local new_name = base_name
  while true do
    local success, err = pcall(vim.api.nvim_buf_set_name, bufnr, new_name)
    if success then
      break
    end
    if err and err:match("Failed to rename buffer") then
      count = count + 1
      new_name = base_name .. count
    else
      break
    end
  end
end

-- Open a new buffer and write unique LSP References of word under cursor
vim.api.nvim_create_user_command('Refs', function()
  local function on_list(list)
    local lines = {}
    local seen = {}
    local prefix = "^/Users/robcmills/src/openspace/web/icedemon/"

    for _, item in ipairs(list.items) do
      local path = string.gsub(item.filename, prefix, "")
      if not seen[path] then
        seen[path] = true
        table.insert(lines, path)
      end
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    set_unique_buffer_name(bufnr, 'Refs')
    vim.api.nvim_set_current_buf(bufnr)
  end
  vim.lsp.buf.references(nil, { on_list = on_list })
end, {})


local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Open a new buffer and write qflist
-- To dump telecope results into qflist, in normal mode use `ctrl + q` (twice)
vim.api.nvim_create_user_command('Qf', function()
  local qflist = vim.fn.getqflist()
  local lines = {}
  for _, qf in ipairs(qflist) do
    local filepath = vim.fn.bufname(qf.bufnr)
    table.insert(lines, string.format("%s:%s:%s | %s", filepath, qf.lnum, qf.col, trim(qf.text)))
  end
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  set_unique_buffer_name(bufnr, 'qf')
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = 'qf'
end, {})

-- Open a new buffer and write diagnostics from current buffer
vim.api.nvim_create_user_command('Diagnostics', function()
  local diagnostics = vim.inspect(vim.diagnostic.get(0))
  local lines = vim.split(diagnostics, '\n')
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  set_unique_buffer_name(bufnr, 'Diagnostics')
  vim.api.nvim_set_current_buf(bufnr)
end, {})


-- git

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

vim.keymap.set('n', '<leader>gs', ':term git status<cr>', { desc = 'Git status' })

vim.keymap.set('n', '<leader>gd', function()
  vim.cmd('Git diff')
end, { desc = 'Git diff' })

vim.keymap.set('n', '<leader>gc', function()
  vim.cmd('vsplit')
  vim.cmd('Git add --all')
  vim.cmd('Git commit')
  vim.api.nvim_command('wincmd w')
  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(current_win, false)
end, { desc = 'Git commit' })

vim.keymap.set('n', '<leader>gp', function()
  vim.cmd('Git push')
end, { desc = 'Git push' })


-- Treat .ejs files as .html
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
  pattern = "*.ejs",
  command = "set filetype=html",
})

-- Treat .frag and .vert shader files as .glsl
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
   pattern = { "*.frag", "*.vert" },
   command = "set filetype=glsl",
})


-- Global find and replace (preview)
-- ! grep -rl --exclude-dir=node_modules "i18next-init" ./ | xargs sed -n 's/i18next-init/i18next-init-with-translations/gp'

-- Global find and replace (commit)
-- ! grep -rl --exclude-dir=node_modules "i18next-init" ./ | xargs sed -i 's/i18next-init/i18next-init-with-translations/gp'

-- arglist
-- :arg *.html - Populate the arglist with all html files in the current working directory, and edit the first one.
-- :argadd *.twig - Add twig files to the arglist.
-- :argdo %s/pattern/replace/ge | update - Replace pattern in every file of the arglist.


-- nvim-pvg
vim.keymap.set('n', '<leader>v', ':lua require("nvim-pvg").search()<cr>', { desc = 'pvg' })

-- copilot
vim.keymap.set("i", "<C-l>", function()
  vim.cmd("Copilot panel")
end, { desc = "Copilot Panel" })

-- sessions

-- save session
-- :mksession! ~/.config/nvim/sessions/session-name.vim

-- load session
-- :source ~/.config/nvim/sessions/session-name.vim

-- set window size
-- first set "fixed" height so changes persist
-- :setlocal winfixheight / winfixwidth
-- then set height
-- :resize 20
-- or width
-- :vertical resize 80

-- open command-line window (to see history of commands)
-- :<C-f>
-- optionally filter history
-- :filter /s/
-- yank to system clipboard
-- "*y
