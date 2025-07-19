--[[
A neovim plugin called "vertical-buffers-list" that renders the open buffers in a vertical split. 
Inspired by vertical tabs sidebars in some browsers (Arc, Brave).

Current behaviors:

Renders only filenames, unless the filename is index.* or duplicates exist, in which case it renders the name of the parent directory like so:
```
fileA.ts
fileB.ts
ParenDir/index.ts
```

Each buffer has a "shortcut" letter rendered next to it, like so:
```
a fileA.ts
b fileB.ts
c ParenDir/index.ts
```
When the buffers window is focused, pressing one of the letters should open the corresponding buffer.
The shortcut letters ascend alphabetically based on the order in which the buffers were focused.

It renders buffers top to bottom in the order they were opened by default, but it is modifiable by the user to manually reorder them, and any changes made persist.

Buffer names are colored based on their focus order:
- Most recently active buffer (a): white (configurable)
- Previously active buffer (b): soft (configurable)
- All other buffers: gray (configurable)

Buffers window width is configurable to either a fixed width or auto.

The window can be displayed in three positions:
- "left": Vertical split on the left side (default)
- "right": Vertical split on the right side
- "float": Centered floating window that closes when a buffer is selected

It exposes methods to:
- show/focus the buffer list (with optional position argument)
- hide the buffer list
- re-order the buffers

The code is as simple and minimal as possible.
The code is written in lua.


## TODO:

- bug: double letter shortcuts don't work because "ab" just jumps to "a" on first keypress
- bug: shortcut lettering to a buffer should open in _last focused window_
- add config option to exclude letters from shortcuts
  + debug why q shortcut doesn't work
- add config option to exclude filenames and filetypes
- enable clicking on buffer name to open it
- add debug log to file
- add option to show buffers list in a floating window (even if sidebar is open)
- when a buffer is deleted, update cursor position in buffers window
- fix repeated calls to :BuffersMove* not working
- handle :file renames
- handle filesystem changes (e.g. rm, mv, cp)
- fix issues with saving/loading sessions
- enable arbitrary edits to buffers list and reconcile (oil.nvim)
- when deleting a buffer in nvim-tree, if deleted buffer is active, then its window is closed, causing the buffers window to become "full screen" and get into a bad state. Perhaps when selecting a buffer, make a check to see if the "last active" buffer has a window, and if not create one.
- quickfind buffer appears in buffers list

]]

--[[
Example configuration:

require('buffers').setup({
  width = 'auto',
  min_width = 25, -- minimum width when using auto width (default: 25)
  side = "left", -- "left" or "right" (default: "left")
  colors = {
    error = { link = "ErrorMsg" }, -- Buffers with LSP errors (overrides other colors)
    modified = { link = "WarningMsg" }, -- Buffers with unsaved changes
    active = { link = "Normal" }, -- Most recently active buffer (a)
    previous = { link = "Title" }, -- Previously active buffer (b)
    inactive = { link = "Comment" }, -- All other buffers
  }
})

Usage:
- :BuffersShow - Show buffer list using default position (left)
- :BuffersShow left - Show buffer list on the left
- :BuffersShow right - Show buffer list on the right
- :BuffersShow float - Show buffer list in a floating window
- :BuffersShowLeft - Show buffer list on the left
- :BuffersShowRight - Show buffer list on the right
- :BuffersShowFloat - Show buffer list in a floating window

Colors values are highlight definition maps (see nvim_set_hl):
]]

local M = {}

local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

local function get_devicon(name)
  if not devicons_ok then
    return "", nil
  end
  local icon, hl = devicons.get_icon(name, nil, { default = true })
  return icon or "", hl
end

---@class BuffersState
---@field win number|nil Window handle for the buffers window
---@field buf number|nil Buffer handle for the buffers buffer
---@field buffer_order number[] Array of buffer numbers in the order they were opened/tracked
---@field focus_order number[] Array of buffer numbers in focus order (most recent first)
---@field letter_map table<string, number>|nil Mapping from shortcut letters to buffer numbers
---@field config BuffersConfig Configuration options

---@class BuffersConfig
---@field width number|string Width of the buffers window (number or 'auto')
---@field min_width number|nil Minimum width when using auto width (default: 20)
---@field side string Side of the screen to show buffers window ("left" or "right", default: "left")
---@field colors BuffersColors Color configuration

---@class BuffersColors (see nvim_set_hl)
---@field error table Highlight definition for buffers with LSP errors
---@field modified table Highlight definition for buffers with unsaved changes
---@field active table Highlight definition for the most recently active buffer
---@field previous table Highlight definition for the previously active buffer
---@field inactive table Highlight definition for all other buffers

---@class BuffersState
local state = {
  win = nil,
  buf = nil,
  buffer_order = {}, -- Array of buffer numbers in order they were opened (modifiable by user)
  focus_order = {}, -- Array of buffer numbers in focus order (most recent first)
  config = {
    width = 'auto',
    min_width = 25, -- minimum width when using auto width (default: 25)
    side = 'left', -- default to left side
    colors = {
      error = { link = "ErrorMsg" }, -- Buffers with LSP errors (overrides other colors)
      modified = { link = "WarningMsg" }, -- Buffers with unsaved changes
      active = { link = "Normal" }, -- Most recently active buffer (a)
      previous = { link = "Title" }, -- Previously active buffer (b)  
      inactive = { link = "Comment" }, -- All other buffers
    }
  }
}

-- Set up highlight groups for buffer colors
local function setup_highlights()
  vim.api.nvim_set_hl(0, "BuffersActive", state.config.colors.active)
  vim.api.nvim_set_hl(0, "BuffersPrevious", state.config.colors.previous)
  vim.api.nvim_set_hl(0, "BuffersInactive", state.config.colors.inactive)
  vim.api.nvim_set_hl(0, "BuffersError", state.config.colors.error)
  vim.api.nvim_set_hl(0, "BuffersModified", state.config.colors.modified)
end

-- Get display name for buffer
local function get_buffer_name(bufnr, all_buffers)
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  if name == "" then
    return "[No Name]"
  end

  -- Check for duplicate names among all buffers
  local has_duplicate = false
  if all_buffers then
    for _, other_bufnr in ipairs(all_buffers) do
      if other_bufnr ~= bufnr then
        local other_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(other_bufnr), ":t")
        if other_name == name then
          has_duplicate = true
          break
        end
      end
    end
  end

  -- Include parent directory for index files or duplicates
  if name:match("^index%.") or has_duplicate then
    local parent = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h:t")
    return parent .. "/" .. name
  end

  return name
end

-- Get letter for index (a-z, then aa-az, ba-bz, etc.)
local function get_letter(index)
  if index <= 26 then
    return string.char(96 + index)
  else
    local prefix = math.floor((index - 1) / 26)
    local suffix = ((index - 1) % 26) + 1
    return get_letter(prefix) .. string.char(96 + suffix)
  end
end

-- Check if buffer has LSP diagnostic errors
local function has_diagnostic_errors(bufnr)
  local diagnostics = vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })
  return #diagnostics > 0
end

-- Check if buffer has unsaved changes
local function has_unsaved_changes(bufnr)
  return vim.bo[bufnr].modified
end

-- Update focus order when buffer is entered
local function update_focus_order(bufnr)
  -- Remove from current position
  for i, buf in ipairs(state.focus_order) do
    if buf == bufnr then
      table.remove(state.focus_order, i)
      break
    end
  end
  -- Add to front
  table.insert(state.focus_order, 1, bufnr)
end

local function get_ordered_buffers()
  local buffers = {}

  for _, bufnr in ipairs(state.buffer_order) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      table.insert(buffers, bufnr)
    end
  end

  return buffers
end

-- Calculate auto width based on buffer names
local function calculate_auto_width()
  local buffers = get_ordered_buffers()
  local max_width = state.config.min_width or 25 -- minimum width

  if #buffers == 0 then
    return max_width
  end

  -- Sort by focus order for letter assignment (same logic as render function)
  local letter_order = {}
  for _, bufnr in ipairs(buffers) do
    table.insert(letter_order, bufnr)
  end
  table.sort(letter_order, function(a, b)
    local a_pos = #state.focus_order + 1
    local b_pos = #state.focus_order + 1
    for i, buf in ipairs(state.focus_order) do
      if buf == a then a_pos = i end
      if buf == b then b_pos = i end
    end
    return a_pos < b_pos
  end)

  -- Create letter mapping (same as render function)
  local letter_map = {}
  for i, bufnr in ipairs(letter_order) do
    letter_map[bufnr] = get_letter(i)
  end

  -- Calculate width for each buffer line
  for _, bufnr in ipairs(buffers) do
    local name = get_buffer_name(bufnr, buffers)
    local letter = letter_map[bufnr]
    local icon, _ = get_devicon(name)
    -- Format: "letter icon name" + 1 margin column
    local icon_len = icon ~= "" and (string.len(icon) + 1) or 0
    local line_width = string.len(letter) + 1 + icon_len + string.len(name) + 1
    max_width = math.max(max_width, line_width)
  end

  return max_width
end

-- Get effective width (auto or configured)
local function get_effective_width()
  if state.config.width == 'auto' then
    return calculate_auto_width()
  else
    return state.config.width
  end
end

-- Move cursor to active buffer line in buffers window
local function move_cursor_to_active_buffer()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local buffers = get_ordered_buffers()

  -- Find the line number for the current buffer
  for line_idx, bufnr in ipairs(buffers) do
    if bufnr == current_bufnr then
      -- Set cursor to the line with the active buffer, column 0 (shortcut letter)
      vim.api.nvim_win_set_cursor(state.win, {line_idx, 0})
      break
    end
  end
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local buffers = get_ordered_buffers()

  -- Sort by focus order for letter assignment
  local letter_order = {}
  for _, bufnr in ipairs(buffers) do
    table.insert(letter_order, bufnr)
  end
  table.sort(letter_order, function(a, b)
    local a_pos = #state.focus_order + 1
    local b_pos = #state.focus_order + 1
    for i, buf in ipairs(state.focus_order) do
      if buf == a then a_pos = i end
      if buf == b then b_pos = i end
    end
    return a_pos < b_pos
  end)

  -- Create letter mapping
  local letter_map = {}
  for i, bufnr in ipairs(letter_order) do
    letter_map[bufnr] = get_letter(i)
  end

  -- Render lines
  local lines = {}

  for _, bufnr in ipairs(buffers) do
    local name = get_buffer_name(bufnr, buffers)
    local letter = letter_map[bufnr]
    local icon, _ = get_devicon(name)
    if icon ~= "" then
      table.insert(lines, string.format("%s %s %s", letter, icon, name))
    else
      table.insert(lines, string.format("%s %s", letter, name))
    end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  -- vim.bo[state.buf].modifiable = false

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)

  -- Highlight group
  for line_idx, bufnr in ipairs(buffers) do
    local hl_group
    if has_diagnostic_errors(bufnr) then
      hl_group = "BuffersError"
    elseif has_unsaved_changes(bufnr) then
      hl_group = "BuffersModified"
    else
      local focus_pos = nil
      for i, buf in ipairs(state.focus_order) do
        if buf == bufnr then
          focus_pos = i
          break
        end
      end

      if focus_pos == 1 then
        hl_group = "BuffersActive"    -- Most recently active (a)
      elseif focus_pos == 2 then
        hl_group = "BuffersPrevious"  -- Previously active (b)
      else
        hl_group = "BuffersInactive"  -- All others
      end
    end

    -- Calculate the start and end positions for the buffer name
    local name = get_buffer_name(bufnr, buffers)
    local letter = letter_map[bufnr]
    local icon, icon_hl = get_devicon(name)

    local name_start
    if icon ~= "" then
      local icon_start = string.len(letter) + 1
      local icon_end = icon_start + string.len(icon)
      if icon_hl then
        vim.api.nvim_buf_set_extmark(state.buf, vim.api.nvim_create_namespace("buffers_icons"),
          line_idx - 1, icon_start, {
            end_col = icon_end,
            hl_group = icon_hl
          })
      end
      name_start = icon_end + 1
    else
      name_start = string.len(letter) + 1
    end

    local name_end = name_start + string.len(name)

    -- Apply highlight to the buffer name only
    vim.api.nvim_buf_set_extmark(state.buf, vim.api.nvim_create_namespace("buffers_colors"),
      line_idx - 1, name_start, {
        end_col = name_end,
        hl_group = hl_group
      })
  end

  -- Store letter mapping for navigation
  state.letter_map = {}
  for bufnr, letter in pairs(letter_map) do
    state.letter_map[letter] = bufnr
  end

  -- Update window width if auto width is enabled
  if state.config.width == 'auto' and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_width(state.win, get_effective_width())
  end

  move_cursor_to_active_buffer()
end

-- Create buffer window
local function create_window(position)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  -- Set up highlight groups
  setup_highlights()

  -- Check if buffer already exists
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    local filename = vim.fn.fnamemodify(buf_name, ":t")
    if filename == "VerticalBuffersList" then
      state.buf = bufnr
      break
    end
  end

  -- Create buffer if it doesn't exist
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].swapfile = false
    vim.api.nvim_buf_set_name(state.buf, "VerticalBuffersList")
  end

  -- Create window based on position
  if position == "float" then
    -- Create floating window
    local width = get_effective_width()
    local height = math.min(20, #get_ordered_buffers()) -- Limit height, add 2 for padding

    local ui = vim.api.nvim_list_uis()[1]
    local screen_width = ui.width
    local screen_height = ui.height

    local win_width = math.min(width, screen_width - 4)
    local win_height = math.min(height, screen_height - 4)

    local row = math.floor((screen_height - win_height) / 2)
    local col = math.floor((screen_width - win_width) / 2)

    local opts = {
      relative = "editor",
      width = win_width,
      height = win_height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded"
    }

    state.win = vim.api.nvim_open_win(state.buf, true, opts)
  else
    -- Create split window
    vim.cmd("vsplit")
    if position == "right" then
      vim.cmd("wincmd L")
    else
      vim.cmd("wincmd H")
    end

    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(state.win, get_effective_width())
    vim.wo[state.win].winfixwidth = true
  end

  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].foldcolumn = "0"
  vim.wo[state.win].list = false
  vim.wo[state.win].wrap = false

  -- Set up keymaps for navigation
  for i = 1, 26 do
    local letter = string.char(96 + i)
    vim.api.nvim_buf_set_keymap(state.buf, "n", letter, "", {
      callback = function()
        if state.letter_map and state.letter_map[letter] then
          local target_bufnr = state.letter_map[letter]

          if position == "float" then
            -- For floating window, close it and switch to target buffer
            vim.api.nvim_win_close(state.win, true)
            state.win = nil
            vim.api.nvim_set_current_buf(target_bufnr)
          else
            -- For split windows, find another window and switch to target buffer
            local current_win = vim.api.nvim_get_current_win()
            local wins = vim.api.nvim_list_wins()
            for _, win in ipairs(wins) do
              if win ~= current_win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_set_buf(win, target_bufnr)
                vim.api.nvim_set_current_win(win)
                break
              end
            end
          end
        end
      end,
      noremap = true,
      silent = true
    })
  end

  -- Add Escape key to close floating window
  if position == "float" then
    vim.api.nvim_buf_set_keymap(state.buf, "n", "<Esc>", "", {
      callback = function()
        vim.api.nvim_win_close(state.win, true)
        state.win = nil
      end,
      noremap = true,
      silent = true
    })

    vim.api.nvim_buf_set_keymap(state.buf, "n", "q", "", {
      callback = function()
        vim.api.nvim_win_close(state.win, true)
        state.win = nil
      end,
      noremap = true,
      silent = true
    })
  end

  render()
end

-- Track new buffers
local function track_buffer(bufnr)
  if not vim.tbl_contains(state.buffer_order, bufnr) then
    table.insert(state.buffer_order, bufnr)
    update_focus_order(bufnr)
  end
end

-- Public functions
---@param position string|nil Position for the buffer window ("left", "right", or "float")
function M.show(position)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    render()
  else
    -- Use provided position or fall back to config side
    local window_position = position or state.config.side
    create_window(window_position)
  end
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.next()
  local buffers = get_ordered_buffers()
  if #buffers <= 1 then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_index = nil

  -- Find current buffer index in buffer_order
  for i, bufnr in ipairs(buffers) do
    if bufnr == current_bufnr then
      current_index = i
      break
    end
  end

  if current_index then
    -- Move to next buffer (wrap around to beginning)
    local next_index = (current_index % #buffers) + 1
    local next_bufnr = buffers[next_index]
    vim.api.nvim_set_current_buf(next_bufnr)
    render()
  end
end

function M.previous()
  local buffers = get_ordered_buffers()
  if #buffers <= 1 then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_index = nil

  -- Find current buffer index in buffer_order
  for i, bufnr in ipairs(buffers) do
    if bufnr == current_bufnr then
      current_index = i
      break
    end
  end

  if current_index then
    -- Move to previous buffer (wrap around to end)
    local prev_index = current_index == 1 and #buffers or current_index - 1
    local prev_bufnr = buffers[prev_index]
    vim.api.nvim_set_current_buf(prev_bufnr)
    render()
  end
end

function M.movePrev()
  local buffers = get_ordered_buffers()
  if #buffers <= 1 then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_index = nil

  -- Find current buffer index in buffer_order
  for i, bufnr in ipairs(state.buffer_order) do
    if bufnr == current_bufnr then
      current_index = i
      break
    end
  end

  if current_index and current_index > 1 then
    -- Move current buffer one position up (towards beginning)
    local buffer_to_move = state.buffer_order[current_index]
    table.remove(state.buffer_order, current_index)
    table.insert(state.buffer_order, current_index - 1, buffer_to_move)
    render()
  end
end

function M.moveNext()
  local buffers = get_ordered_buffers()
  if #buffers <= 1 then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_index = nil

  -- Find current buffer index in buffer_order
  for i, bufnr in ipairs(state.buffer_order) do
    if bufnr == current_bufnr then
      current_index = i
      break
    end
  end

  if current_index and current_index < #state.buffer_order then
    -- Move current buffer one position down (towards end)
    local buffer_to_move = state.buffer_order[current_index]
    table.remove(state.buffer_order, current_index)
    table.insert(state.buffer_order, current_index + 1, buffer_to_move)
    render()
  end
end

---@param config BuffersConfig|nil
function M.setup(config)
  -- Merge config
  if config then
    if config.colors then
      state.config.colors = vim.tbl_extend("force", state.config.colors, config.colors)
    end
    if config.width then
      state.config.width = config.width
    end
    if config.min_width then
      state.config.min_width = config.min_width
    end
    if config.side then
      state.config.side = config.side
    end
  end

  setup_highlights()

  -- Set up user commands
  vim.api.nvim_create_user_command("BuffersShow", function(args)
    M.show(args.args ~= "" and args.args or nil)
  end, {
    desc = "Show buffer list (optional: left, right, or float)",
    nargs = "?"
  })

  vim.api.nvim_create_user_command("BuffersShowLeft", function()
    M.show("left")
  end, {
    desc = "Show buffer list on the left"
  })

  vim.api.nvim_create_user_command("BuffersShowRight", function()
    M.show("right")
  end, {
    desc = "Show buffer list on the right"
  })

  vim.api.nvim_create_user_command("BuffersShowFloat", function()
    M.show("float")
  end, {
    desc = "Show buffer list in a floating window"
  })

  vim.api.nvim_create_user_command("BuffersHide", M.hide, {
    desc = "Hide buffer list"
  })

  vim.api.nvim_create_user_command("BuffersNext", M.next, {
    desc = "Navigate to next buffer"
  })

  vim.api.nvim_create_user_command("BuffersPrev", M.previous, {
    desc = "Navigate to previous buffer"
  })

  vim.api.nvim_create_user_command("BuffersMovePrev", M.movePrev, {
    desc = "Move current buffer up in the buffer order"
  })

  vim.api.nvim_create_user_command("BuffersMoveNext", M.moveNext, {
    desc = "Move current buffer down in the buffer order"
  })

  -- Set up autocmds
  local group = vim.api.nvim_create_augroup("BuffersPlugin", { clear = true })

  -- Track new buffers
  vim.api.nvim_create_autocmd("BufAdd", {
    group = group,
    callback = function(args)
      track_buffer(args.buf)
    end
  })

  -- Track focus changes
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      update_focus_order(args.buf)
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        render()
      end
    end
  })

  -- Update on buffer changes
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
    group = group,
    callback = function(e)
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        -- remove deleted buffer from buffer_order
        for i, buf in ipairs(state.buffer_order) do
          if buf == e.buf then
            table.remove(state.buffer_order, i)
            break
          end
        end
        -- remove deleted buffer from focus_order
        for i, buf in ipairs(state.focus_order) do
          if buf == e.buf then
            table.remove(state.focus_order, i)
            break
          end
        end
        vim.defer_fn(render, 10)
      end
    end
  })

  -- Update on diagnostic changes
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.defer_fn(render, 10)
      end
    end
  })

  -- Update when buffer modified state changes
  vim.api.nvim_create_autocmd("BufModifiedSet", {
    group = group,
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        render()
      end
    end
  })

  -- Track existing buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      track_buffer(bufnr)
    end
  end
end

return M
