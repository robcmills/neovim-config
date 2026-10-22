--[[
A neovim plugin called "vertical-buffers-list" that renders the open buffers in a vertical split. 
Inspired by vertical tabs sidebars in some browsers (Arc, Brave).

Current behaviors:

Renders only filenames, unless the filename is index.* or duplicates exist,
in which case it renders the name of the parent directory like so:
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
When the buffers window is focused, pressing one of the letters opens the corresponding buffer.
The shortcut letters ascend alphabetically based on the order in which the buffers were focused.

cc.nvim agent buffers (output and prompt) are listed first, then file
buffers. Agent rows are sorted by project priority from
`jarvis priorities --json` (see agent_priority.lua): level 1 to 5 (5 and
up), then unknown, then by effective priority, ties keeping their manual order. File
buffers are rendered top to bottom in the order they were opened by default,
and the order is modifiable by the user to manually reorder them. Manual
reordering moves a row only past a neighbor in its own group (and, for
agents, of equal priority).

Agent rows show the agent's colored status icon in the icon column instead of a
devicon, and the session name (the buffer name until cc.nvim names the
session), colored by level in rainbow order: orange, yellow, cyan, light
blue, gray, and a dimmer gray for unknown (`priority_colors`).
Only the current buffer's name is pure white, and bold.

File buffer names are colored based on their focus order:
- Most recently active buffer (a): white (configurable)
- Previously active buffer (b): soft (configurable)
- All other buffers: gray (configurable)

The cursor in the buffers window sits on the current buffer's row after every
render, unless the buffers window itself is focused, where it stays on the
row of the buffer it was on.

The buffers window sets 'winfixbuf', so no other buffer can be opened in it.

:FocusNext focuses the highest-priority unread agent in this Neovim
(level, then effective priority, then unread longest). With nothing unread
it cycles the ready agents in sidebar order: from a ready row it goes to the
next one down, wrapping to the first; from anywhere else, to the first.

Buffers window width is configurable to either a fixed width or auto,
with min and max width configurable settings.

The window can be displayed in three positions:
- "left": Vertical split on the left side (default)
- "right": Vertical split on the right side
- "float": Centered floating window that closes when a buffer is selected

It exposes methods to:
- show/focus the buffer list (with optional position argument)
- hide the buffer list
- re-order the buffers

The code is as simple and minimal as possible.


## TODO:

- bug: solve shortcuts when length of buffers list is greater than available keys
    i.e double letter shortcuts don't work because "ab" just jumps to "a" on first keypress
- enhancement: enable arbitrary edits to buffers list and reconcile (oil.nvim) ?
- enhancement: add config option to exclude letters from shortcuts (or fix delays)
  + e.g. the "g" shortcut always delays because it is the first letter of "sequence keybindings"
  + debug why q shortcut doesn't work
- enhancement: add config option to exclude filenames and filetypes
- enhancement: enable mouse support (i.e. clicking on buffer name to open it) (gross)
- add debug mode config option (logs to a file)
- add option to show buffers list in a floating window (even if sidebar is open)
- when a buffer is deleted, update cursor position in buffers window
- bug: fix repeated calls to :BuffersMove* not working (update internal order state when buffers are closed/deleted)
- handle filesystem changes (e.g. rm, mv, cp)
- fix issues with saving/loading sessions (that include terminal buffers)
- when deleting a buffer in nvim-tree, if deleted buffer is active, then its window is closed, causing the buffers window to become "full screen" and get into a bad state. Perhaps when selecting a buffer, make a check to see if the "last active" buffer has a window, and if not create one.

]]

--[[
Example configuration:

require('buffers').setup({
  width = 'auto',
  min_width = 25, -- minimum width when using auto width (default: 25)
  max_width = 40, -- maximum width when using auto width (default: nil, no limit)
  side = "left", -- "left" or "right" (default: "left")
  colors = {
    error = { link = "ErrorMsg" }, -- Buffers with LSP errors (overrides other colors)
    modified = { link = "WarningMsg" }, -- Buffers with unsaved changes
    active = { link = "Normal" }, -- Most recently active buffer (a)
    previous = { link = "Title" }, -- Previously active buffer (b)
    inactive = { link = "Comment" }, -- All other buffers
  },
  -- Optional: override agent row colors by level (1-5), unknown or current
  priority_colors = { unknown = "#6c717c" },
  -- Command printing agent priorities as JSON (default below)
  priority_cmd = { "jarvis", "priorities", "--json" },
  -- Optional: format display names (may return newlines for wrapping)
  format_file_name = function(filepath, display_name)
    -- Example: drop a "cc-" prefix, then wrap after an ISO timestamp prefix
    display_name = display_name:gsub("^cc%-", "")
    local ts, rest = display_name:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%-)(.*)")
    if ts then
      return ts .. "\n" .. rest
    end
    return display_name
  end,
})

Colors values are _highlight definition maps_ (see nvim_set_hl):

Usage:
- :BuffersShow - Show buffer list using default position (left)
- :BuffersShow left - Show buffer list on the left
- :BuffersShow right - Show buffer list on the right
- :BuffersShow float - Show buffer list in a floating window
- :BuffersShowLeft - Show buffer list on the left
- :BuffersShowRight - Show buffer list on the right
- :BuffersShowFloat - Show buffer list in a floating window
- :BuffersMarkUnread - Mark the cc.nvim agent under the cursor (or the current
  buffer) unread until next viewed; `U` in the buffers window does the same
- :FocusNext - Focus the highest-priority unread cc.nvim agent, else the next ready one

]]

local M = {}

local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
local priority = require("agent_priority")

local state -- forward declaration; initialized below

local function get_devicon(name, bufnr)
  -- Check icon overrides first (supports Lua patterns)
  if state.config.icons and state.config.icons.override then
    for key, entry in pairs(state.config.icons.override) do
      if name:match(key) then
        local hl = entry.hl
        if not hl and entry.color then
          hl = "BuffersIcon_" .. key:gsub("[^%w]", "")
          vim.api.nvim_set_hl(0, hl, { fg = entry.color })
        end
        return entry.icon or "", hl
      end
    end
  end
  -- Check if buffer is a terminal (after overrides, so specific terminal names can have custom icons)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == 'terminal' then
    local terminal_config = state.config.icons and state.config.icons.terminal
    if terminal_config then
      return terminal_config.icon or "", terminal_config.hl
    end
  end
  -- Fall back to nvim-web-devicons
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
---@field icons table|nil Config for nvim-web-devicons
---@field width? number|string Width of the buffers window (number or 'auto')
---@field min_width? number|nil Minimum width when using auto width (default: 25)
---@field max_width? number|nil Maximum width when using auto width (default: 40)
---@field side? string Side of the screen to show buffers window ("left" or "right", default: "left")
---@field colors? BuffersColors Color configuration
---@field format_file_name? fun(filepath: string, display_name: string): string Optional function to format display names (may return newlines for wrapping)
---@field priority_cmd? string[] Command printing agent priorities as JSON
---@field priority_colors? table<integer|string, string> Agent row colors by level, "unknown" and "current" (see PRIORITY_COLORS)

---@class BuffersColors (see nvim_set_hl)
---@field error table Highlight definition for buffers with LSP errors
---@field modified table Highlight definition for buffers with unsaved changes
---@field active table Highlight definition for the most recently active buffer
---@field previous table Highlight definition for the previously active buffer
---@field inactive table Highlight definition for all other buffers

---@class BuffersState
state = {
  win = nil,
  buf = nil,
  buffer_order = {}, -- Array of buffer numbers in order they were opened (modifiable by user)
  focus_order = {}, -- Array of buffer numbers in focus order (most recent first)
  buf_first_lines = {}, -- Maps bufnr to first display line number (set during render)
  config = {
    icons = {},
    width = 'auto',
    min_width = 25, -- minimum width when using auto width (default: 25)
    max_width = 40, -- maximum width when using auto width (default: 50)
    side = 'left', -- default to left side
    colors = {
      error = { link = "ErrorMsg" }, -- Buffers with LSP errors (overrides other colors)
      modified = { link = "WarningMsg" }, -- Buffers with unsaved changes
      active = { link = "Normal" }, -- Most recently active buffer (a)
      previous = { link = "Title" }, -- Previously active buffer (b)  
      inactive = { link = "Comment" }, -- All other buffers
    },
    priority_colors = {},
  }
}

-- Agent row name colors by level (agent_priority.lua), in rainbow order
local PRIORITY_COLORS = {
  "#ff9e64", -- 1: orange
  "#ffe14d", -- 2: yellow
  "#4fd6be", -- 3: cyan
  "#89c4ff", -- 4: light blue
  "#9aa0aa", -- 5 and up: gray
  unknown = "#737884", -- dimmer gray
  current = "#ffffff", -- the current buffer's row, whatever its level (bold)
}
M.PRIORITY_COLORS = PRIORITY_COLORS

-- Highlight group for an agent row's name
local function priority_hl(level, current)
  if current then
    return "BuffersPriorityCurrent"
  end
  return "BuffersPriority" .. (level or "Unknown")
end

-- Status icons for cc.nvim agent buffers, keyed by cc.nvim instance state.
-- Single-cell Nerd Font glyphs, so agent rows align with devicon rows.
local AGENT_STATUS_ICONS = {
  waiting = { icon = "󰹇", color = "#f0a85a" },      -- md-hand_back_right
  interrupting = { icon = "󰏃", color = "#f04848" }, -- md-octagon
  working = { icon = "󱌢", color = "#e8c547" },      -- md-hammer_wrench
  delegating = { icon = "", color = "#c678dd" },   -- fa-sitemap
  monitoring = { icon = "", color = "#56b6c2" },   -- fa-heartbeat
  unread = { icon = "󰇮", color = "#61afef" },       -- md-email
  starting = { icon = "󰹦", color = "#a8d08d" },     -- md-sprout
  ready = { icon = "", color = "#5fd35f" },        -- fa-circle
  exited = { icon = "󰚌", color = "#7f848e" },       -- md-skull
}

local function status_hl(agent_state)
  return "BuffersStatus_" .. agent_state
end

-- Set up highlight groups for buffer colors
local function setup_highlights()
  vim.api.nvim_set_hl(0, "BuffersActive", state.config.colors.active)
  vim.api.nvim_set_hl(0, "BuffersPrevious", state.config.colors.previous)
  vim.api.nvim_set_hl(0, "BuffersInactive", state.config.colors.inactive)
  vim.api.nvim_set_hl(0, "BuffersError", state.config.colors.error)
  vim.api.nvim_set_hl(0, "BuffersModified", state.config.colors.modified)
  local colors = vim.tbl_extend("force", PRIORITY_COLORS, state.config.priority_colors)
  for level = 1, priority.LEVELS do
    vim.api.nvim_set_hl(0, priority_hl(level), { fg = colors[level] })
  end
  vim.api.nvim_set_hl(0, priority_hl(nil), { fg = colors.unknown })
  vim.api.nvim_set_hl(0, priority_hl(nil, true), { fg = colors.current, bold = true })
  for agent_state, entry in pairs(AGENT_STATUS_ICONS) do
    vim.api.nvim_set_hl(0, status_hl(agent_state), { fg = entry.color })
  end
end

local function setup_icons()
  require("nvim-web-devicons").setup(state.config.icons)
end

local function list_instances()
  local cc = package.loaded["cc"]
  if not cc or not cc.list_instances then
    return {}
  end
  local ok, instances = pcall(cc.list_instances)
  return ok and instances or {}
end

-- Map bufnr -> cc.nvim instance snapshot for every agent output and prompt buffer
local function get_agents()
  local agents = {}
  for _, inst in ipairs(list_instances()) do
    agents[inst.outputBufnr] = inst
    agents[inst.promptBufnr] = inst
  end
  return agents
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

-- Listed buffers in display order: agent rows sorted by priority (ties keep
-- buffer_order), then file rows in buffer_order. Also returns, per agent
-- row, { level, key } (see agent_priority.lua).
local function get_ordered_buffers(agents)
  agents = agents or get_agents()
  local agent_rows, files, info = {}, {}, {}
  for i, bufnr in ipairs(state.buffer_order) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local inst = agents[bufnr]
      if inst then
        local level, effective = priority.of(inst)
        info[bufnr] = { level = level, key = priority.key(level, effective) }
        table.insert(agent_rows, { bufnr = bufnr, index = i })
      else
        table.insert(files, bufnr)
      end
    end
  end
  table.sort(agent_rows, function(a, b)
    local before = priority.before(info[a.bufnr].key, info[b.bufnr].key)
    if before == nil then
      return a.index < b.index
    end
    return before
  end)

  local buffers = {}
  for _, row in ipairs(agent_rows) do
    table.insert(buffers, row.bufnr)
  end
  vim.list_extend(buffers, files)
  return buffers, info
end

-- The row the current buffer belongs to: the current buffer, or else the
-- most recently focused buffer that has a row. An agent's prompt buffer maps
-- to its output buffer's row.
local function get_active_row(buffers, agents)
  local rows = {}
  for _, bufnr in ipairs(buffers) do
    rows[bufnr] = true
  end
  local candidates = { vim.api.nvim_get_current_buf() }
  vim.list_extend(candidates, state.focus_order)
  for _, bufnr in ipairs(candidates) do
    if rows[bufnr] then
      return bufnr
    end
    local inst = agents[bufnr]
    if inst and rows[inst.outputBufnr] then
      return inst.outputBufnr
    end
  end
end

-- Lay out every row: its lines, the byte columns of its icon and name, and
-- the width the window needs. The icon column is as wide as the widest icon,
-- so names align on every row.
local function build_layout()
  local agents = get_agents()
  local buffers, info = get_ordered_buffers(agents)

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

  local entries = {}
  local letter_width, icon_width = 0, 0
  for _, bufnr in ipairs(buffers) do
    local name = get_buffer_name(bufnr, buffers)
    local icon, icon_hl
    if agents[bufnr] then
      local status = AGENT_STATUS_ICONS[agents[bufnr].state]
      if status then
        icon, icon_hl = status.icon, status_hl(agents[bufnr].state)
      else
        icon = ""
      end
    else
      icon, icon_hl = get_devicon(name, bufnr)
    end

    -- Agent rows show the session name; before cc.nvim names the session,
    -- and for files, the buffer name through format_file_name if configured
    local session_name = agents[bufnr] and agents[bufnr].name
    local display_name = name
    if type(session_name) == "string" and session_name ~= "" then
      display_name = session_name
    elseif state.config.format_file_name then
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      display_name = state.config.format_file_name(filepath, display_name)
    end

    local entry = {
      bufnr = bufnr,
      name = name,
      name_parts = vim.split(display_name, "\n", { plain = true }),
      letter = letter_map[bufnr],
      icon = icon,
      icon_hl = icon_hl,
      agent = info[bufnr],
    }
    letter_width = math.max(letter_width, string.len(entry.letter))
    icon_width = math.max(icon_width, vim.api.nvim_strwidth(icon))
    table.insert(entries, entry)
  end

  -- First line: "letter icon name"; continuation lines indented to the name.
  -- Every line gets 1 margin column in the width.
  local lines = {}
  local width = state.config.min_width or 25
  for _, entry in ipairs(entries) do
    local prefix = entry.letter .. string.rep(" ", letter_width - string.len(entry.letter)) .. " "
    entry.icon_col = string.len(prefix)
    if icon_width > 0 then
      prefix = prefix .. entry.icon .. string.rep(" ", icon_width - vim.api.nvim_strwidth(entry.icon)) .. " "
    end
    entry.name_col = string.len(prefix)
    entry.first_line = #lines + 1
    entry.num_lines = #entry.name_parts

    local indent = string.rep(" ", vim.api.nvim_strwidth(prefix))
    for i, part in ipairs(entry.name_parts) do
      local line = (i == 1 and prefix or indent) .. part
      table.insert(lines, line)
      width = math.max(width, vim.api.nvim_strwidth(line) + 1)
    end
  end

  -- Apply max_width limit if configured
  if state.config.max_width then
    width = math.min(width, state.config.max_width)
  end

  return {
    agents = agents,
    buffers = buffers,
    entries = entries,
    lines = lines,
    letter_map = letter_map,
    width = width,
    active = get_active_row(buffers, agents),
  }
end

-- Calculate auto width based on buffer names
local function calculate_auto_width()
  return build_layout().width
end

-- Get effective width (auto or configured)
local function get_effective_width()
  if state.config.width == 'auto' then
    return calculate_auto_width()
  else
    return state.config.width
  end
end

-- The window showing the buffers list, or nil when it is hidden. Another
-- buffer can be loaded into the list's window (cc.nvim stages a new session
-- in the current window), so check what state.win shows, and follow the list
-- if it has moved to another window.
local function list_win()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil
  end
  if not (state.win and vim.api.nvim_win_is_valid(state.win)
      and vim.api.nvim_win_get_buf(state.win) == state.buf) then
    local win = vim.fn.bufwinid(state.buf)
    state.win = win ~= -1 and win or nil
  end
  return state.win
end

-- Put the buffers window cursor on `bufnr`'s row
local function move_cursor_to_buffer(bufnr)
  if not list_win() then
    return
  end
  local first_line = bufnr and state.buf_first_lines[bufnr]
  if first_line then
    vim.api.nvim_win_set_cursor(state.win, {first_line, 0})
  end
end

-- The buffer whose row is under the buffers window cursor
local function buffer_under_cursor()
  if not list_win() or not state.line_bufs then
    return nil
  end
  return state.line_bufs[vim.api.nvim_win_get_cursor(state.win)[1]]
end

-- Extend the cursorline over the continuation lines of the row under the
-- cursor, so a wrapped row is highlighted whole
local function highlight_cursor_row()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local ns = vim.api.nvim_create_namespace("buffers_cursor_row")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  local bufnr = buffer_under_cursor()
  local first_line = bufnr and state.buf_first_lines[bufnr]
  if not first_line then
    return
  end
  local line = first_line + 1
  while state.line_bufs[line] == bufnr do
    vim.api.nvim_buf_set_extmark(state.buf, ns, line - 1, 0, { line_hl_group = "CursorLine" })
    line = line + 1
  end
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  -- With the buffers window focused, the cursor follows the buffer it was on
  -- through a re-sort; otherwise it goes to the current buffer's row
  local sidebar_focused = list_win() == vim.api.nvim_get_current_win()
  local cursor_bufnr = sidebar_focused and buffer_under_cursor() or nil

  local layout = build_layout()
  local lines = layout.lines
  local buf_entries = layout.entries

  -- Store first-line mapping for cursor positioning, and the reverse
  -- (every display line, including continuations) for cursor lookups
  state.buf_first_lines = {}
  state.line_bufs = {}
  for _, entry in ipairs(buf_entries) do
    state.buf_first_lines[entry.bufnr] = entry.first_line
    for i = 0, entry.num_lines - 1 do
      state.line_bufs[entry.first_line + i] = entry.bufnr
    end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)

  -- Highlight groups
  for _, entry in ipairs(buf_entries) do
    local bufnr = entry.bufnr
    local hl_group
    if entry.agent then
      hl_group = priority_hl(entry.agent.level, bufnr == layout.active)
    elseif has_diagnostic_errors(bufnr) then
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

    local line_idx = entry.first_line

    -- Highlight first line: icon + name
    if entry.icon ~= "" and entry.icon_hl then
      vim.api.nvim_buf_set_extmark(state.buf, vim.api.nvim_create_namespace("buffers_icons"),
        line_idx - 1, entry.icon_col, {
          end_col = entry.icon_col + string.len(entry.icon),
          hl_group = entry.icon_hl
        })
    end

    vim.api.nvim_buf_set_extmark(state.buf, vim.api.nvim_create_namespace("buffers_colors"),
      line_idx - 1, entry.name_col, {
        end_col = string.len(lines[line_idx]),
        hl_group = hl_group
      })

    -- Highlight continuation lines
    for i = 2, entry.num_lines do
      local cont_line_idx = entry.first_line + i - 1
      local cont_line = lines[cont_line_idx]
      local text_start = cont_line:find("%S")
      if text_start then
        vim.api.nvim_buf_set_extmark(state.buf, vim.api.nvim_create_namespace("buffers_colors"),
          cont_line_idx - 1, text_start - 1, {
            end_col = string.len(cont_line),
            hl_group = hl_group
          })
      end
    end
  end

  -- Store letter mapping for navigation
  state.letter_map = {}
  for bufnr, letter in pairs(layout.letter_map) do
    state.letter_map[letter] = bufnr
  end

  -- Update window width if auto width is enabled
  if state.config.width == 'auto' and list_win() then
    vim.api.nvim_win_set_width(state.win, layout.width)
  end

  move_cursor_to_buffer(cursor_bufnr or layout.active)
  highlight_cursor_row()
end

-- Create buffer window
local function create_window(position)
  if list_win() then
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
    -- Display line count (accounts for multiline formatted names)
    local display_lines = #build_layout().lines
    local height = math.min(20, display_lines)

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
  -- No other buffer can be opened in the buffers window
  vim.wo[state.win].winfixbuf = true

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
            -- Skip windows showing unlisted buffers (e.g. companion panes, NvimTree)
            local current_win = vim.api.nvim_get_current_win()
            local wins = vim.api.nvim_list_wins()
            local target_win = nil
            for _, win in ipairs(wins) do
              if win ~= current_win and vim.api.nvim_win_is_valid(win)
                 and vim.bo[vim.api.nvim_win_get_buf(win)].buflisted then
                target_win = win
                break
              end
            end
            if target_win then
              vim.api.nvim_win_set_buf(target_win, target_bufnr)
              vim.api.nvim_set_current_win(target_win)
            else
              -- No suitable window found (main window was closed) — create a new split
              -- Place new window opposite to the buffers list side
              if position == "right" then
                vim.cmd("leftabove vsplit")
              else
                vim.cmd("rightbelow vsplit")
              end
              vim.api.nvim_set_current_buf(target_bufnr)
              -- Restore buffers window width
              if list_win() then
                vim.api.nvim_win_set_width(state.win, get_effective_width())
              end
            end
          end
        end
      end,
      noremap = true,
      silent = true
    })
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = vim.api.nvim_create_augroup("BuffersCursorRow", { clear = true }),
    buffer = state.buf,
    callback = highlight_cursor_row,
  })

  -- U marks the agent under the cursor unread
  vim.api.nvim_buf_set_keymap(state.buf, "n", "U", "", {
    callback = function() M.mark_unread() end,
    noremap = true,
    silent = true
  })

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
  priority.refresh()
  if list_win() then
    vim.api.nvim_set_current_win(state.win)
    render()
  else
    -- Use provided position or fall back to config side
    local window_position = position or state.config.side
    create_window(window_position)
  end
end

-- Mark a cc.nvim agent unread until next viewed: the row under the cursor
-- when in the buffers window, otherwise the current buffer
function M.mark_unread()
  local bufnr = vim.api.nvim_get_current_buf()
  if bufnr == state.buf then
    bufnr = state.line_bufs and state.line_bufs[vim.api.nvim_win_get_cursor(0)[1]]
  end
  local cc = package.loaded["cc"]
  if not (bufnr and cc and cc.mark_unread and cc.mark_unread(bufnr)) then
    vim.notify("Not a cc.nvim agent buffer", vim.log.levels.WARN)
  end
end

function M.hide()
  if list_win() then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

-- Pick the buffer that next/prev should navigate relative to. If the current
-- buffer is listed, use it. Otherwise (e.g. focused on buffers list or
-- cc.nvim output), fall back to the most recently focused listed buffer.
local function get_reference_buffer(buffers)
  local current_bufnr = vim.api.nvim_get_current_buf()
  for _, bufnr in ipairs(buffers) do
    if bufnr == current_bufnr then
      return current_bufnr
    end
  end
  local listed_set = {}
  for _, bufnr in ipairs(buffers) do
    listed_set[bufnr] = true
  end
  for _, bufnr in ipairs(state.focus_order) do
    if listed_set[bufnr] then
      return bufnr
    end
  end
  return buffers[1]
end

-- Switch to target_bufnr. If the current window holds a listed buffer, swap
-- it there. Otherwise, find another window with a listed buffer and swap
-- there; create a split if none exists.
local function switch_to_buffer(target_bufnr)
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  if vim.bo[current_buf].buflisted then
    vim.api.nvim_set_current_buf(target_bufnr)
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= current_win and vim.api.nvim_win_is_valid(win)
       and vim.bo[vim.api.nvim_win_get_buf(win)].buflisted then
      vim.api.nvim_win_set_buf(win, target_bufnr)
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  if state.config.side == "right" then
    vim.cmd("leftabove vsplit")
  else
    vim.cmd("rightbelow vsplit")
  end
  vim.api.nvim_set_current_buf(target_bufnr)
  if list_win() then
    vim.api.nvim_win_set_width(state.win, get_effective_width())
  end
end

function M.next()
  local buffers = get_ordered_buffers()
  if #buffers == 0 then
    return
  end

  local reference_bufnr = get_reference_buffer(buffers)
  local current_index
  for i, bufnr in ipairs(buffers) do
    if bufnr == reference_bufnr then
      current_index = i
      break
    end
  end

  if current_index then
    local next_index = (current_index % #buffers) + 1
    switch_to_buffer(buffers[next_index])
    render()
  end
end

function M.previous()
  local buffers = get_ordered_buffers()
  if #buffers == 0 then
    return
  end

  local reference_bufnr = get_reference_buffer(buffers)
  local current_index
  for i, bufnr in ipairs(buffers) do
    if bufnr == reference_bufnr then
      current_index = i
      break
    end
  end

  if current_index then
    local prev_index = current_index == 1 and #buffers or current_index - 1
    switch_to_buffer(buffers[prev_index])
    render()
  end
end

-- Swap the current buffer's row with its neighbor `delta` rows away, when
-- both are file rows, or both agent rows of equal priority (the sort decides
-- everything else). The swap is made in buffer_order, which breaks ties.
local function move(delta)
  local buffers, info = get_ordered_buffers()
  if #buffers <= 1 then
    return
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  local index
  for i, bufnr in ipairs(buffers) do
    if bufnr == current_bufnr then
      index = i
      break
    end
  end
  local neighbor = index and buffers[index + delta]
  if not neighbor then
    return
  end
  local a, b = info[current_bufnr], info[neighbor]
  if (a == nil) ~= (b == nil) or (a and priority.before(a.key, b.key) ~= nil) then
    return
  end

  local pos = {}
  for i, bufnr in ipairs(state.buffer_order) do
    pos[bufnr] = i
  end
  local i, j = pos[current_bufnr], pos[neighbor]
  state.buffer_order[i], state.buffer_order[j] = neighbor, current_bufnr
  render()
end

function M.movePrev()
  move(-1)
end

function M.moveNext()
  move(1)
end

-- Focus the unread cc.nvim agent of highest priority (then unread longest)
-- the way the buffers list opens a row. With nothing unread, cycle the ready
-- agent rows in sidebar order: from a ready row, the next one down (wrapping
-- to the first); from anywhere else, the first. The current row is the only
-- state, so repeated calls walk the list. Waits briefly for a fresh priority
-- fetch, and falls back to the cached one.
function M.focus_next()
  priority.refresh()
  priority.wait(400)
  local inst = priority.pick_unread(list_instances())
  local target = inst and inst.outputBufnr
  if not target then
    local agents = get_agents()
    local buffers = get_ordered_buffers(agents)
    local ready = {}
    for _, bufnr in ipairs(buffers) do
      if agents[bufnr] and agents[bufnr].state == "ready" then
        table.insert(ready, bufnr)
      end
    end
    if #ready == 0 then
      vim.notify("Nothing unread or ready")
      return
    end
    local active = get_active_row(buffers, agents)
    local index = 1
    for i, bufnr in ipairs(ready) do
      if bufnr == active then
        index = i % #ready + 1
        break
      end
    end
    target = ready[index]
    if target == active then
      vim.notify("Nothing unread; the only ready agent")
      return
    end
    vim.notify(("Nothing unread; ready %d/%d"):format(index, #ready))
  end
  switch_to_buffer(target)
  render()
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
    if config.max_width then
      state.config.max_width = config.max_width
    end
    if config.icons then
      state.config.icons = config.icons
    end
    if config.format_file_name then
      state.config.format_file_name = config.format_file_name
    end
    if config.priority_colors then
      state.config.priority_colors = config.priority_colors
    end
  end

  priority.setup({
    cmd = config and config.priority_cmd,
    on_change = function()
      if list_win() then
        render()
      end
    end,
  })

  setup_highlights()

  setup_icons()

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

  vim.api.nvim_create_user_command("BuffersMarkUnread", M.mark_unread, {
    desc = "Mark the selected cc.nvim agent unread until next viewed"
  })

  vim.api.nvim_create_user_command("FocusNext", M.focus_next, {
    desc = "Focus the highest-priority unread cc.nvim agent, else the next ready one"
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
      if list_win() then
        render()
      end
      if get_agents()[args.buf] then
        priority.refresh()
      end
    end
  })

  -- Priorities may have changed outside Neovim (e.g. a project re-tagged)
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = priority.refresh
  })

  -- Update on buffer changes
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
    group = group,
    callback = function(e)
      if list_win() then
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
      if list_win() then
        vim.defer_fn(render, 10)
      end
    end
  })

  -- Update when buffer modified state changes
  vim.api.nvim_create_autocmd("BufModifiedSet", {
    group = group,
    callback = function()
      if list_win() then
        render()
      end
    end
  })

  -- Update when a terminal is opened (buftype isn't set during BufAdd/BufEnter)
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function()
      if list_win() then
        vim.defer_fn(render, 10)
      end
    end
  })

  -- Update when a buffer is renamed (e.g. :file newname)
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = group,
    callback = function()
      if list_win() then
        render()
      end
    end
  })

  -- Re-render when a cc.nvim agent changes state, and refetch priorities (a
  -- new session may be tagged). Every render reads all agent states fresh,
  -- so any render also corrects a missed event.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CcStateChanged",
    callback = function()
      if list_win() then
        render()
      end
      priority.refresh()
    end
  })

  -- Re-sync all agent states when a buffer is added (e.g. a new cc.nvim agent)
  vim.api.nvim_create_autocmd("BufAdd", {
    group = group,
    callback = function()
      if list_win() then
        vim.defer_fn(render, 10)
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
