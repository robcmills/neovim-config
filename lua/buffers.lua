--[[
A neovim plugin called "vertical-buffers" that renders the open buffers on the right in a vertical split. 
Inspired by vertical tabs sidebars in some browsers (Arc, Brave).

Current behaviors:

Renders only filenames, unless the filename is index.*, in which case it renders the name of the parent directory like so:
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
The shortcut letters should be ascending alphabetically based on the order in which the buffers were focused.

It renders buffers top to bottom in the order they were opened by default, but it is modifiable by the user to manually reorder them, and any changes made persist.

Buffer names are colored based on their focus order:
- Most recently active buffer (a): white (configurable)
- Previously active buffer (b): soft cyan (configurable)
- All other buffers: gray (configurable)

It is configurable with custom keybindings and colors.

Buffers window is a configurable fixed width (default 50).

It exposes methods to:
- show/focus the buffer list
- hide the buffer list

The code is as simple and minimal as possible.
The code is written in lua.

TODO:
  - enable showing diagnostics in the buffer list (red if there are errors)
  - implement buffer next/prev commands
  - enable modifying buffers list manually (reorder)
  - when deleting a buffer in nvim-tree, if deleted buffer is active, then its window is closed,
    causing the buffers window to become "full screen" and get into a bad state.
    Perhaps when selecting a buffer, make a check to see if the "last active" buffer has a window,
    and if not create one.
  - show parent dir if a buffer name is duplicated in the list
]]

--[[
Example configuration:

require('buffers').setup({
  keybindings = {
    show = "<leader>b",
    hide = "<leader>B",
  },
  width = 50,
  colors = {
    active = { link = "Normal" }, -- Most recently active buffer (a)
    previous = { link = "Title" }, -- Previously active buffer (b)
    inactive = { link = "Comment" }, -- All other buffers
  }
})

Colors values are highlight definition maps (see nvim_set_hl):
]]

local M = {}

local state = {
  win = nil,
  buf = nil,
  buffer_order = {},
  focus_order = {},
  custom_order = {},
  config = {
    keybindings = {
      show = "<leader>b",
      hide = "<leader>B",
    },
    width = 50,
    colors = {
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
end

-- Get display name for buffer
local function get_buffer_name(bufnr)
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  if name == "" then
    return "[No Name]"
  elseif name:match("^index%.") then
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

-- Get ordered buffer list
local function get_ordered_buffers()
  local buffers = {}

  -- Use custom order if available, otherwise use buffer_order
  local order = #state.custom_order > 0 and state.custom_order or state.buffer_order

  for _, bufnr in ipairs(order) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      table.insert(buffers, bufnr)
    end
  end

  return buffers
end

-- Render buffer list
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = {}
  local buffers = get_ordered_buffers()
  local alternate_bufnr = vim.fn.bufnr('#')

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
  for _, bufnr in ipairs(buffers) do
    local name = get_buffer_name(bufnr)
    local letter = letter_map[bufnr]
    local indicator
    if bufnr == vim.api.nvim_get_current_buf() then
      indicator = "%"
    elseif bufnr == alternate_bufnr then
      indicator = "#"
    else
      indicator = " "
    end
    table.insert(lines, string.format("%s %s %s", letter, indicator, name))
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)

  -- Apply colors based on focus order
  for line_idx, bufnr in ipairs(buffers) do
    local name = get_buffer_name(bufnr)
    local letter = letter_map[bufnr]

    -- Determine highlight group based on focus order
    local hl_group
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

    -- Calculate the start and end positions for the buffer name
    local name_start = string.len(letter) + 3  -- letter + " " + indicator + " "
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
end

-- Create buffer window
local function create_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  -- Set up highlight groups
  setup_highlights()

  -- Get or create buffer
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].swapfile = false
    -- vim.api.nvim_buf_set_name(state.buf, "Buffers")
  end

  -- Create window
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, state.config.width)
  vim.wo[state.win].winfixwidth = true
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
          -- Find the previously focused window (not the current buffer list window)
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
function M.show()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  else
    create_window()
  end
  render()
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

function M.setup(config)
  -- Merge config
  if config then
    if config.keybindings then
      state.config.keybindings = vim.tbl_extend("force", state.config.keybindings, config.keybindings)
    end
    if config.colors then
      state.config.colors = vim.tbl_extend("force", state.config.colors, config.colors)
    end
    if config.width then
      state.config.width = config.width
    end
  end

  -- Set up highlight groups
  setup_highlights()

  -- Set up keybindings
  vim.api.nvim_set_keymap("n", state.config.keybindings.show, "", {
    callback = M.show,
    noremap = true,
    silent = true,
    desc = "Show buffer list"
  })

  vim.api.nvim_set_keymap("n", state.config.keybindings.hide, "", {
    callback = M.hide,
    noremap = true,
    silent = true,
    desc = "Hide buffer list"
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
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
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
