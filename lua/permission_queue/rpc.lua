-- Act on a queued prompt in the Neovim that owns it: answer it, open its
-- agent, or read the agent's last message. Local calls when the owner is this
-- Neovim; otherwise `nvim --server <socket> --remote-expr`, async with a
-- timeout so a wedged Neovim can't hang this one.
local M = {}

local function is_local(item) return item.nvim_pid == vim.fn.getpid() end

--- Run `require('cc').<fn>(args...)` in the owner; cb(result_string, err).
local function remote(item, fn, args, cb)
  local list = {}
  for _, a in ipairs(args) do list[#list + 1] = vim.fn.string(a) end
  local expr = ("luaeval('vim.inspect(require(\"cc\").%s(unpack(_A)))', [%s])")
    :format(fn, table.concat(list, ', '))
  vim.system({ 'nvim', '--server', item.socket, '--remote-expr', expr },
    { text = true, timeout = 5000 }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then return cb(nil, (res.stderr ~= '' and res.stderr) or 'nvim --server failed') end
        cb(vim.trim(res.stdout or ''))
      end)
    end)
end

--- Answer a prompt. cb(true) when it was still pending and is now answered.
---@param behavior 'allow'|'deny'
function M.resolve(item, behavior, cb)
  if is_local(item) then
    return cb(require('cc').resolve_permission(item.id, behavior) == true)
  end
  remote(item, 'resolve_permission', { item.id, behavior }, function(out, err)
    cb(out == 'true', err)
  end)
end

--- Bring the agent forward: its tmux window, then its prompt float.
function M.open(item)
  if item.pane then
    vim.system({ 'tmux', 'select-window', '-t', item.pane }):wait(2000)
    vim.system({ 'tmux', 'select-pane', '-t', item.pane }):wait(2000)
  end
  if is_local(item) then return require('cc').focus_instance(item.output_bufnr) end
  remote(item, 'focus_instance', { item.output_bufnr }, function() end)
end

--- The agent's last assistant message, as lines (empty on failure).
function M.tail(item, cb)
  vim.system({ 'agents', 'tail', 'key=' .. item.key }, { text = true, timeout = 5000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then return cb({}) end
      cb(vim.split(vim.trim(res.stdout or ''), '\n', { plain = true }))
    end)
  end)
end

return M
