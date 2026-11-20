-- The count of pending permission prompts in every Neovim, for the
-- statusline (g:permission_queue_count). Event-driven: every Neovim already
-- pokes each `<pid>.sock` in the agents picker directory on cc.nvim's
-- CcStateChanged (~/.config/agents/src/picker-notify.lua), and a prompt
-- opening or being answered changes its agent's state. So this Neovim
-- listens there under its own pid and recounts on each poke, debounced;
-- FocusGained and startup recount too, covering anything missed.
local M = {}

local uv = vim.uv
local DEBOUNCE_MS = 300

function M.set(n)
  if vim.g.permission_queue_count == n then return end
  vim.g.permission_queue_count = n
  vim.cmd('redrawstatus!')
end

---@param load fun(cb: fun(items: table, total: integer))
function M.listen(load)
  local timer = uv.new_timer()
  local function recount()
    timer:stop()
    timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function() load(function() end) end))
  end

  local dir = vim.env.AGENTS_PICKER_DIR
  if not dir or dir == '' then dir = '/tmp/agents-picker.' .. (vim.env.USER or 'unknown') end
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/' .. vim.fn.getpid() .. '.sock'
  uv.fs_unlink(path)
  local server = uv.new_pipe(false)
  local ok = server and server:bind(path) and server:listen(16, function(err)
    if err then return end
    local client = uv.new_pipe(false)
    server:accept(client)
    -- The connection is the message; picker-notify hangs up at once.
    client:read_start(function(_, data) if not data then client:close() end end)
    recount()
  end)
  if not ok then
    vim.notify('permission queue: cannot listen on ' .. path, vim.log.levels.WARN)
  end

  local group = vim.api.nvim_create_augroup('permission_queue_badge', { clear = true })
  vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = recount })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function() if server then server:close() end; uv.fs_unlink(path) end,
  })
  recount()
end

return M
