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
    width = 40,
  }
}

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
    local current = bufnr == vim.api.nvim_get_current_buf() and "*" or " "
    table.insert(lines, string.format("%s %s %s", letter, current, name))
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

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
  create_window()
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
  if config and config.keybindings then
    state.config.keybindings = vim.tbl_extend("force", state.config.keybindings, config.keybindings)
  end

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
