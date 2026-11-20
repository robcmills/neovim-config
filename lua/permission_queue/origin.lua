-- Where Rob was when he opened the permission queue, so finishing it puts
-- him back: the tmux pane, the Neovim window and buffer, the cursor, and
-- whether he was typing (insert mode).
local M = {}

---@class PermissionQueueOrigin
---@field pane string?
---@field win integer
---@field buf integer
---@field cursor integer[]
---@field insert boolean

---@return PermissionQueueOrigin
function M.save()
  local win = vim.api.nvim_get_current_win()
  -- Opened from a float (another popup): come back to the window under it.
  if vim.api.nvim_win_get_config(win).relative ~= '' then win = vim.fn.win_getid(vim.fn.winnr('#')) end
  return {
    pane = vim.env.TMUX_PANE,
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    cursor = vim.api.nvim_win_get_cursor(win),
    insert = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i',
  }
end

---@param o PermissionQueueOrigin
function M.restore(o)
  if o.pane then
    vim.system({ 'tmux', 'select-window', '-t', o.pane }):wait(2000)
    vim.system({ 'tmux', 'select-pane', '-t', o.pane }):wait(2000)
  end
  if not vim.api.nvim_win_is_valid(o.win) then return end
  vim.api.nvim_set_current_win(o.win)
  if vim.api.nvim_buf_is_valid(o.buf) and vim.api.nvim_win_get_buf(o.win) ~= o.buf then
    pcall(vim.api.nvim_win_set_buf, o.win, o.buf)
  end
  pcall(vim.api.nvim_win_set_cursor, o.win, o.cursor)
  if not o.insert then return end
  -- Insert mode's cursor can sit past the last character; normal mode
  -- clamps it, so resume with `A` semantics there.
  local line = vim.api.nvim_buf_get_lines(o.buf, o.cursor[1] - 1, o.cursor[1], false)[1] or ''
  vim.cmd(o.cursor[2] >= #line and 'startinsert!' or 'startinsert')
end

return M
