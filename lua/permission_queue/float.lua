-- The queue's float: one prompt at a time, rendered like cc.nvim's own
-- permission float (same title and body), plus which agent asks, how long it
-- has waited, and the agent's last message. Keys call `actions[key]()`.
-- Leaving the float (WinLeave) only closes it, like `g`: nothing answers.
local M = {}

local KEYS = { 'a', 'd', 's', 'o', 'g', 'q', '<Esc>' }
local FOOTER = ' [a]llow  [d]eny  [s]kip  [o]pen agent  [g]o elsewhere  [q]uit '

local state = { win = nil, buf = nil }

local function age(opened_at)
  local s = math.max(0, os.time() - opened_at)
  if s < 60 then return s .. 's' end
  if s < 3600 then return math.floor(s / 60) .. 'm' end
  return math.floor(s / 3600) .. 'h' .. math.floor(s % 3600 / 60) .. 'm'
end

function M.close()
  local win = state.win
  state.win, state.buf = nil, nil
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
end

---@param item PermissionQueueItem
---@param pos integer
---@param total integer
---@param actions table<string, fun()>
---@return integer bufnr lines can be appended to (the agent's message)
function M.show(item, pos, total, actions)
  M.close()
  local pp = require('cc.permission_prompt')
  local lines = { pp._build_title(item.tool_name, item.input,
    item.kind == 'denial' and '⛔ Blocked by auto mode' or '⚠ Permission'), '' }
  local body = pp._body_lines(item.tool_name, item.input)
  -- cc.nvim leaves a Bash command with no description out of the body (the
  -- title has it, cut at 100 characters). Show all of it: an ask-rob detail
  -- lives past that cut.
  if body[1] == '(no input)' and type(item.input.command) == 'string' then
    body = vim.split(item.input.command, '\n', { plain = true })
  end
  vim.list_extend(lines, body)
  vim.list_extend(lines, { '', '── ' .. item.name .. '\'s last message ──', '(loading…)' })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = math.min(120, math.max(60, math.floor(vim.o.columns * 0.8)))
  local height = math.max(8, math.min(#lines + 12, math.floor(vim.o.lines * 0.75)))
  local where = item.project ~= '' and (' (' .. item.project .. ')') or ''
  local title = (' Permission %d of %d waiting · %s%s · %s%s '):format(pos, total, item.name,
    where, age(item.opened_at), item.deferred and ' · deferred' or '')
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height, style = 'minimal', border = 'rounded',
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    title = { { title, 'CcPermission' } }, title_pos = 'center',
    footer = FOOTER, footer_pos = 'center',
  })
  vim.wo[win].wrap = true
  state.win, state.buf = win, buf
  -- Opened from the Jarvis prompt mid-typing (voice runs the command over
  -- RPC in any mode): the keys below are normal-mode maps. The origin
  -- already recorded insert mode, and restoring it resumes typing.
  vim.cmd('stopinsert')

  for _, key in ipairs(KEYS) do
    local action = actions[key == '<Esc>' and 'q' or key]
    vim.keymap.set('n', key, function() action() end, { buffer = buf, nowait = true, silent = true })
  end
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf, once = true,
    callback = function() vim.schedule(function() if state.win == win then M.close() end end) end,
  })
  return buf
end

--- Replace the "(loading…)" placeholder with the agent's message.
function M.set_message(buf, message_lines)
  if buf ~= state.buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if #message_lines == 0 then message_lines = { '(none)' } end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -2, -1, false, message_lines)
  vim.bo[buf].modifiable = false
end

return M
