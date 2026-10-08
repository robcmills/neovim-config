-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

require 'plugins'
require 'configs.tokyonight'
require 'colemak'
require 'ref-tree'
require('claude-code-session-tree').setup()

-- Sweep stale shada tmp files left over from ungraceful nvim exits, so the
-- a..z suffix pool can't fill up and trigger E138 on the next quit.
vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('shada_tmp_sweep', { clear = true }),
  callback = function()
    local dir = vim.fn.stdpath('state') .. '/shada'
    local now = os.time()
    for _, f in ipairs(vim.fn.glob(dir .. '/main.shada.tmp.*', false, true)) do
      local st = vim.uv.fs_stat(f)
      if st and now - st.mtime.sec > 60 then
        pcall(os.remove, f)
      end
    end
  end,
})

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
vim.opt.belloff = ""
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


-- vim.keymap.set("i", "<Tab>", "<Esc>")
vim.keymap.set("n", "U", "<C-r>", { desc = "Redo" })
vim.keymap.set("n", "<C-j>", "gJi <ESC>ciW <ESC>", { desc = "Join lines (and remove excess whitespace)" })
-- vim.keymap.set("n", "s", ":bufdo if empty(getbufvar(bufnr(), '&buftype')) | w | endif<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>yf", ":let @+ = expand('%')<cr>", { desc = "Copy current buffer filepath" })
vim.keymap.set("n", "<leader>q", ":qa!<cr>", { desc = "Quit all" })
vim.keymap.set("n", "<C-q>", ":q<cr>", { desc = "Quit" })
vim.keymap.set("n", "<leader>h", ":nohlsearch<cr>", { desc = "No Highlight" })
vim.keymap.set("n", "<leader>A", "gg0vG$y", { desc = "Copy all" })
vim.keymap.set("n", "<leader>'", "ciw''<ESC>P", { desc = "Surround word with single quotes" })
vim.keymap.set("n", '<leader>"', 'ciw""<ESC>P', { desc = "Surround word with double quotes" })
vim.keymap.set("n", "<leader>`", "ciw``<ESC>P", { desc = "Surround word with backticks" })
vim.keymap.set("n", '<leader>(', 'ciw()<ESC>P', { desc = "Surround word with parens" })
vim.keymap.set("n", '<leader>{', 'ciw{}<ESC>P', { desc = "Surround word with curly brackets" })

vim.keymap.set("n", "<leader>d", "ggVGx", { desc = "Clear current buffer" })

vim.keymap.set("n", "s", function()
  -- save all valid, non-terminal buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and
       vim.bo[buf].buflisted and
       vim.bo[buf].buftype ~= 'terminal' and
       vim.bo[buf].modified
    then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd('write')
      end)
    end
  end
end, { desc = "Save" })

vim.keymap.set("n", '<leader>o', function()
  local line = vim.fn.line('.')
  local content = vim.fn.getreg('+')
  local text = "console.log({ " .. content .. " });"
  vim.api.nvim_buf_set_lines(0, line, line, false, {text})
  vim.api.nvim_win_set_cursor(0, {line + 1, 0})
end, { desc = "console.log contents of clipboard" })

local function toggle_boolean()
  local word = vim.fn.expand("<cword>")
  if word == "true" then
    vim.cmd("normal! ciwfalse")
  elseif word == "false" then
    vim.cmd("normal! ciwtrue")
  end
end

vim.keymap.set('n', '!', toggle_boolean, { desc = 'Toggle Boolean' })

-- Find the match of `pattern` on the current line that contains the cursor.
-- Returns the matched text, or nil.
local function match_under_cursor(pattern)
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col('.')
  local start = 0
  while true do
    local match, s, e = unpack(vim.fn.matchstrpos(line, pattern, start))
    if s == -1 then return nil end
    if col > s and col <= e then return match end
    start = e
  end
end

-- Opens the url under the cursor in Brave. Also recognizes bare references
-- like `RAD-15317` (Jira) and `#12567` / `PR 12567` (openspace PR).
local function open_url_in_brave()
  local url = match_under_cursor([=[\vhttps?://[^[:space:]<>"'`)\]]+]=])
  if url then
    url = url:gsub('[.,;:]+$', '')
  end

  if not url then
    local key = match_under_cursor([=[\v<[A-Z][A-Z0-9]+-\d+>]=])
    if key then
      url = 'https://openspaceai.atlassian.net/browse/' .. key
    end
  end

  if not url then
    local ref = match_under_cursor([=[\v\c<%(PR|pull request)>\s*#?\d+|#\d+]=])
    if ref then
      url = 'https://github.com/openspacelabs/openspace/pull/' .. ref:match('%d+$')
    end
  end

  if not url then
    vim.notify('No url, Jira key, or PR number under cursor', vim.log.levels.WARN)
    return
  end
  vim.fn.jobstart({ 'open', '-a', 'Brave Browser', url }, { detach = true })
end

vim.keymap.set('n', 'gu', open_url_in_brave, { desc = 'Open url under cursor in Brave' })

-- terminal
vim.opt.scrollback = 5000
vim.o.shell = "bash -l" -- use "login" bash to source .bash_profile
-- vim.o.shell = "/Applications/fish.app/Contents/Resources/base/usr/local/bin/fish"

vim.keymap.set('n', '<leader>t', function()
  vim.cmd('term')
  vim.cmd('startinsert')
end, { desc = 'Open a terminal buffer' })

vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit insert mode in terminal' })
-- for use with agent tuis (e.g. claude code) that bind escape to essential commands
vim.keymap.set('t', '<C-q>', '<Esc>', { desc = 'Send Esc to terminal' })

vim.keymap.set('t', '<C-k>', function()
  vim.fn.feedkeys("", 'n')
  local sb = vim.bo.scrollback
  vim.bo.scrollback = 1
  vim.bo.scrollback = sb
end, { desc = 'Clear terminal' })

vim.api.nvim_create_user_command('Claude', function()
  local base = 'claude'
  local name = base
  -- Find a unique name: claude, claude-1, claude-2, ...
  local i = 1
  while vim.fn.bufnr(name) ~= -1 do
    name = base .. '-' .. i
    i = i + 1
  end
  vim.cmd('term')
  vim.cmd('file ' .. name)
  local chan = vim.bo.channel
  vim.fn.chansend(chan, 'clear && cc\n')
  vim.cmd('startinsert')
end, { desc = 'Open a terminal buffer named claude' })

local terminal_augroup = vim.api.nvim_create_augroup("terminal", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
  group = terminal_augroup,
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = 'no'
  end,
})
vim.api.nvim_create_autocmd("TermClose", {
  group = terminal_augroup,
  callback = function()
    vim.opt_local.number = true
    vim.opt_local.signcolumn = 'yes:1'
  end,
})

-- window nav
vim.keymap.set("n", "<leader>w", "<C-w>w", { desc = "Move to next window", noremap = true })
vim.keymap.set("n", "<leader>W", "<C-w>W", { desc = "Move to prev window", noremap = true })

-- buffers nav
vim.keymap.set("n", "<leader>b", function()
  vim.cmd('NvimTreeClose')
  vim.cmd('BuffersShow')
end, { desc = "Show buffers" })

vim.keymap.set("n", "<leader>v", function()
  vim.cmd('BuffersShowFloat')
end, { desc = "Show buffers in a floating window" })

vim.keymap.set("n", "<leader>B", function()
  vim.cmd('BuffersHide')
end, { desc = "Show buffers" })

vim.keymap.set("n", "t", ":BuffersNext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "T", ":BuffersPrev<cr>", { desc = "Prev buffer" })
vim.keymap.set("n", "<C-e>", ":BuffersMovePrev<cr>", { desc = "Move buffer up" })
vim.keymap.set("n", "<C-n>", ":BuffersMoveNext<cr>", { desc = "Move buffer down" })

vim.keymap.set("n", "<leader>C", function()
  vim.cmd('NvimTreeCollapse')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype ~= "terminal" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end, { desc = "Close all buffers" })

vim.keymap.set("n", "<leader>c", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cc = package.loaded['cc']
  if cc and cc.find_instance(bufnr) then
    vim.cmd('CcClose')
    return
  end
  vim.cmd('bp')
  vim.api.nvim_buf_delete(bufnr, { force = true })
end, { desc = "Close buffer" })

vim.keymap.set("n", "<leader>n", function()
  vim.ui.input({
    prompt = 'Filename: ',
    default = '',
  }, function(filename)
    if filename and filename ~= '' then
      vim.cmd(':e %:h/' .. filename)
      vim.cmd(':w')
    end
  end)
end, { desc = "New buffer" })

vim.api.nvim_create_user_command('Rename', function()
  local old_name = vim.api.nvim_buf_get_name(0)
  local old_filename = vim.fn.fnamemodify(old_name, ':t')
  vim.ui.input({
    prompt = 'New name: ',
    default = old_filename,
  }, function(new_name)
    if new_name ~= '' and new_name ~= old_filename then
      local new_path = vim.fn.fnamemodify(old_name, ':h') .. '/' .. new_name
      vim.fn.rename(old_name, new_path)
      vim.api.nvim_buf_set_name(0, new_path)
      vim.cmd('w!')
    end
  end)
end, { desc = "Rename current file" })

-- winbar
-- vim.opt.winbar = '%f'

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
-- vim.keymap.set("n", "<leader>d", function()
--   require("telescope.builtin").diagnostics()
-- end, { desc = "Search diagnostics" })
-- vim.keymap.set("n", "<leader>b", function()
--   require("telescope.builtin").buffers()
-- end, { desc = "Search buffers" })
vim.keymap.set("n", "<leader>m", function()
  require("telescope.builtin").symbols()
end, { desc = "Symbols" })
vim.keymap.set('n', '<leader>ld', function()
  require('telescope.builtin').lsp_definitions()
end, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ls", function()
  require("telescope.builtin").lsp_document_symbols()
end, { desc = "LSP document symbols" })


-- nvim-tree
vim.keymap.set("n", "<leader>e", function()
  vim.cmd('BuffersHide')
  local bufnr = vim.api.nvim_get_current_buf()
  -- local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  local filetype = vim.bo[bufnr].filetype
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

local function set_unique_buffer_name(bufnr, base_name)
  local count = 1
  local max_count = 1000
  local new_name = base_name
  while count < max_count do
    local success, err = pcall(vim.api.nvim_buf_set_name, bufnr, new_name)
    if success then break end
    if err and (err:match("Failed to rename buffer") or err:match("Buffer with this name already exists")) then
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
    vim.notify("No Git merge conflicts found.\n")
  end
end

vim.keymap.set('n', '<leader>x', function()
  conflicts()
end, { desc = 'Open all files with git merge conflicts' })

vim.keymap.set('n', '<leader>gs', ':term git status<cr>', { desc = 'Git status' })

vim.keymap.set('n', '<leader>gd', function()
  vim.cmd('Git diff')
end, { desc = 'Git diff' })

local function is_merge_commit()
  local merge_head = vim.fn.filereadable(vim.fn.FugitiveGitDir() .. '/MERGE_HEAD')
  return merge_head == 1
end

vim.keymap.set('n', '<leader>gc', function()
  vim.cmd('BuffersHide')
  vim.cmd('vsplit')
  vim.cmd('Git add --all')
  vim.cmd('Git commit')
  vim.api.nvim_command('wincmd w')
  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(current_win, false)
  if not is_merge_commit() then
    vim.cmd('PromptCommitMessage')
  end
end, { desc = 'Git commit' })

vim.keymap.set('n', '<leader>gp', function()
  vim.cmd('Git push')
end, { desc = 'Git push' })

vim.keymap.set('n', '<leader>gmv', function()
  vim.cmd('Git merge development')
end, { desc = 'Git merge development' })

vim.keymap.set("n", "<leader>gf", ":DiffviewOpen<cr>", { desc = "DiffviewOpen" })


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

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight yanked text',
  group = vim.api.nvim_create_augroup('highlight_yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
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
-- vim.keymap.set('n', '<leader>v', ':lua require("nvim-pvg").search()<cr>', { desc = 'pvg' })

-- sessions (:SaveSession / :LoadSession)
require('sessions').setup()

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

-- fix gf: ensure path is correct
-- :set path? -- to see current path
-- :set path=.,** -- to add current directory and all subdirectories

-- execute lua
vim.keymap.set('v', '<leader>u', ':lua<cr>', { desc = 'Execute selected lua' })
-- vim.keymap.set('n', '<leader>u', ':.lua<cr>', { desc = 'Execute current line of lua' })
vim.keymap.set('n', '<leader>u', ':luafile %<cr>', { desc = 'Execute current lua file' })


-- vertical buffers
package.loaded['buffers'] = nil
require('buffers').setup({
  format_file_name = function(filepath, display_name)
    -- cc.nvim buffers get their own icon, so the "cc-" prefix is redundant
    display_name = display_name:gsub("^cc%-", "")
    local ts, rest = display_name:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%-)(.*)")
    if ts then
      return ts .. "\n" .. rest
    end
    return display_name
  end,
  icons = {
    default = true,
    terminal = { icon = "" },
    override = {
      claude = { icon = "✻", color = "#E4A853" },
      ["^cc%-"] = { icon = "✻", color = "#E4A853" },
      ["^cy$"] = { icon = "󰙨", color = "#a3e7cb" },
      ["^git$"] = { icon = "", color = "#F14E32" },
    },
  }
})

vim.api.nvim_create_user_command('BuffersReset', function()
  package.loaded['buffers'] = nil
  require('buffers').setup()
end, { desc = 'Reset Buffers plugin' })


-- require('splash')

vim.api.nvim_create_user_command('Messages', function()
  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false,
    vim.split(vim.fn.execute('messages'), '\n', { plain = true })
  )
end, { desc = 'Dump messages into a new buffer' })

vim.api.nvim_create_user_command('Skills', function()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local entries = {}

  local skills_dir = vim.fn.expand('~/.claude/skills')
  for _, dir in ipairs(vim.fn.glob(skills_dir .. '/*', false, true)) do
    if vim.fn.isdirectory(dir) == 1 then
      local skill_md = dir .. '/SKILL.md'
      if vim.fn.filereadable(skill_md) == 1 then
        local name = vim.fn.fnamemodify(dir, ':t')
        table.insert(entries, {
          display = 'skill   ' .. name,
          path = skill_md,
        })
      end
    end
  end

  local commands_dir = vim.fn.expand('~/.claude/commands')
  for _, file in ipairs(vim.fn.glob(commands_dir .. '/*.md', false, true)) do
    local name = vim.fn.fnamemodify(file, ':t:r')
    table.insert(entries, {
      display = 'command ' .. name,
      path = file,
    })
  end

  pickers.new({}, {
    prompt_title = 'Claude Skills & Commands',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
          path = entry.path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.file_previewer({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          vim.cmd('edit ' .. vim.fn.fnameescape(selection.path))
        end
      end)
      return true
    end,
  }):find()
end, { desc = 'Browse Claude Code skills and commands' })

vim.api.nvim_create_user_command('Hover', function()
  local params = vim.lsp.util.make_position_params(0, 'utf-8')
  vim.lsp.buf_request(0, 'textDocument/hover', params, function(_, result)
    if result and result.contents then
      print(vim.inspect(result))
      local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
      vim.cmd('vsplit')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo.filetype = 'markdown'
    end
  end)
end, { desc = 'Dump hover info into a new buffer' })

-- prompt.nvim
vim.keymap.set('n', '-', ':PromptNew<cr>', { desc = 'New prompt' })
vim.keymap.set('n', '=', ':CcNew<cr>', { desc = 'New cc.nvim chat' })
-- vim.keymap.set('n', '=', function()
--   local bufnr = vim.api.nvim_get_current_buf()
--   require('prompt.core').rename_prompt_summary(bufnr, nil, function()
--     vim.cmd('PromptSubmitClaudeCode')
--   end)
-- end, { desc = 'Rename and submit to claude code' })

-- cc.nvim
-- g:cc_nvim_path points a fresh Neovim at a cc.nvim worktree for testing.
vim.opt.runtimepath:prepend(vim.fn.expand(vim.g.cc_nvim_path or '~/src/cc.nvim'))
require('cc').setup({
  history_max_records = 1000,
  limits_log = '~/.claude/codex-offload/limits.jsonl',
  on_permission_prompt = function(event)
    local tmux_window = 'unknown'
    if vim.env.TMUX_PANE and vim.fn.executable('tmux') == 1 then
      local value = vim.fn.system({
        'tmux', 'display-message', '-p',
        '-t', vim.env.TMUX_PANE,
        '#{window_index}:#{window_name}',
      })
      if vim.v.shell_error == 0 then
        value = vim.trim(value)
        if value ~= '' then tmux_window = value end
      end
    end

    local session = event.output_bufname
      or event.session_name
      or event.session_id
      or 'unknown'
    local message = table.concat({
      'tmux window: ' .. tmux_window,
      'session: ' .. session,
      'permission: ' .. event.tool_name,
    }, '\n')

    if vim.fn.executable('osascript') == 1 then
      vim.system({
        'osascript',
        '-e', [[on run argv
          display notification (item 1 of argv) with title (item 2 of argv)
        end run]],
        message,
        'cc.nvim permission requested',
      })
    else
      vim.notify(message, vim.log.levels.WARN, { title = 'cc.nvim permission requested' })
    end
  end,
  -- Unanswered prompts: after 2 minutes, Remote Control forwards the prompt
  -- to the Claude phone app as a push; 15 minutes later it is denied so the
  -- agent moves on. Override for testing: nvim --cmd 'let g:cc_permission_timeouts = [10, 20]'
  permission_timeouts = {
    {
      after = (vim.g.cc_permission_timeouts or {})[1] or 120,
      callback = function(event) event.enable_remote() end,
    },
    {
      after = (vim.g.cc_permission_timeouts or {})[2] or 900,
      callback = function(event)
        event.resolve('deny', 'Approval timeout. Attempt to work around safely, else continue other work and report this denial.')
      end,
    },
  },
  -- Turn Remote Control back off so the next prompt gets the 2-minute grace.
  on_permission_resolved = function(event)
    if event.remote_enabled_by_stage then event.disable_remote() end
  end,
  prompt_placeholder = 'Enter prompt...',
  provider = 'claude', -- 'claude' | 'codex'
  providers = {
    claude = {
      auto_rename_model = 'haiku',
      cmd = 'cc',
      effort = 'high', -- 'low' | 'medium' | 'high' | 'xhigh' | 'max' | 'auto'
      model = 'opus', -- TODO: back to 'fable' once Brayden lifts the Fable spend limit
      permission_mode = 'bypassPermissions',
    },
    codex = {
      approval_policy = 'never',
      auto_rename_model = 'gpt-5.6-luna',
      effort = 'high',   -- 'low' | 'medium' | 'high' | 'xhigh'
      sandbox = 'danger-full-access',
    },
  },
})
-- vim.keymap.set('n', '<leader>cc', ':CcToggle<cr>', { desc = 'Toggle cc.nvim' })
-- vim.keymap.set('n', '<leader>cs', ':CcSend<cr>', { desc = 'Send cc.nvim prompt' })
-- vim.keymap.set('n', '<leader>cx', ':CcStop<cr>', { desc = 'Stop cc.nvim generation' })

vim.keymap.set('n', '<leader>gmv', function()
  vim.cmd('Git merge development')
end, { desc = 'Git merge development' })

vim.api.nvim_create_user_command('Link', function()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.virtcol('.') -- Get current column (1-indexed)

  -- Check if the character under the cursor is part of a URL
  -- This is a basic heuristic; a more robust solution might involve parsing
  -- or using a dedicated URL detection library.
  local pattern = "([a-zA-Z]+://[%w%p%-%.%?%+%&%=%#%/]*)%f[%s%\"%]?" -- Basic URL pattern

  -- Find the URL containing the cursor position
  for url_match in line:gmatch(pattern) do
    local start_pos, end_pos = line:find(url_match, 1, true) -- Find exact match
    if start_pos and end_pos and col >= start_pos and col <= end_pos then
      vim.fn.system({"brave", url_match})
      return
    end
  end

  -- If no URL found under cursor, try to find the first URL in the line
  local first_url = line:match(pattern)
  if first_url then
    vim.fn.system({"brave", first_url})
    return
  end

  -- If no URL found anywhere, inform the user
  vim.notify("No URL found under cursor or in the current line.", vim.log.levels.WARN)
end, { desc = 'Open the URL under cursor in Brave browser' })

vim.keymap.set('n', '<F5>', ':!love .<cr>', { desc = 'Run Love2d game' })


-- ============================================================================
-- Startup
-- ============================================================================
-- Default workspace: empty buffer + vertical buffers list

vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('startup', { clear = true }),
  callback = function()
    -- Only run when no real file was opened
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.fn.filereadable(buf_name) == 1 then
      return
    end
    -- Replace the initial buffer (`nvim .` leaves a directory buffer, since
    -- netrw is disabled) with a fresh empty one
    local initial_buf = vim.api.nvim_get_current_buf()
    vim.cmd('enew')
    vim.api.nvim_buf_delete(initial_buf, { force = true })

    -- Open vertical buffers list after events propagate
    vim.schedule(function()
      vim.cmd('BuffersShow')
      vim.cmd('wincmd l')
    end)
  end,
})
