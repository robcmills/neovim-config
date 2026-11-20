-- Every pending cc.nvim permission prompt in every Neovim, oldest first, from
-- `agents --json` (one call, ~0.2 s). Each item carries what the queue needs
-- to show it and answer it where it lives: the owning Neovim's socket and
-- pid, its tmux pane, and the agent's output buffer.
local M = {}

---@class PermissionQueueItem
---@field id string request_id in the owning Neovim
---@field kind 'permission'|'denial'
---@field tool_name string
---@field input table
---@field opened_at number
---@field deferred boolean
---@field key string agents key, <nvim-pid>:<output-bufnr>
---@field name string
---@field project string
---@field socket string
---@field nvim_pid integer
---@field pane string? tmux pane id
---@field output_bufnr integer

local function items_from(agents)
  local items = {}
  for _, a in ipairs(agents) do
    for _, p in ipairs(a.pending_permissions or {}) do
      items[#items + 1] = {
        id = tostring(p.request_id), kind = p.kind or 'permission',
        tool_name = p.tool_name or 'unknown', input = p.input or {},
        opened_at = tonumber(p.opened_at) or 0, deferred = p.deferred == true,
        key = a.key, name = type(a.name) == 'string' and a.name or a.key,
        project = a.project or '', socket = a.socketPath, nvim_pid = a.nvimPid,
        pane = type(a.tmuxPaneId) == 'string' and a.tmuxPaneId or nil,
        output_bufnr = a.outputBufnr,
      }
    end
  end
  table.sort(items, function(x, y)
    if x.opened_at ~= y.opened_at then return x.opened_at < y.opened_at end
    return x.key .. x.id < y.key .. y.id
  end)
  return items
end

--- Calls `cb(items, err)` on the main loop.
---@param cb fun(items: PermissionQueueItem[], err: string?)
function M.all(cb)
  vim.system({ 'agents', '--json' }, { text = true, timeout = 10000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then return cb({}, 'agents --json failed: ' .. (res.stderr or res.code)) end
      local ok, agents = pcall(vim.json.decode, res.stdout or '[]')
      if not ok or type(agents) ~= 'table' then return cb({}, 'agents --json: bad JSON') end
      cb(items_from(agents))
    end)
  end)
end

M._items_from = items_from
return M
