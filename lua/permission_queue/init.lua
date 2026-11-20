-- :PermissionPrompts walks every pending cc.nvim permission prompt, in every
-- Neovim, from wherever Rob is, one at a time: a allow, d deny, s skip,
-- o open the agent, g step away (a Chrome login), q quit. The first call
-- saves where he was; the queue running dry, or q, puts him back there.
-- After o or g, running it again resumes the same walk. Voice: "permission
-- prompts". Design: ~/jarvis/scratch/2026-11-19-permission-queue-design.md.
local fetch = require('permission_queue.fetch')
local rpc = require('permission_queue.rpc')
local origin = require('permission_queue.origin')
local float = require('permission_queue.float')

local M = {}

---@type { origin: PermissionQueueOrigin?, skipped: table<string, true>, busy: boolean }
local walk = { origin = nil, skipped = {}, busy = false }

local function id_of(item) return item.key .. '/' .. item.id end

--- Pending prompts not skipped in this walk. Also feeds the badge count.
local function load(cb)
  fetch.all(function(items, err)
    if err then vim.notify('permission queue: ' .. err, vim.log.levels.WARN) end
    require('permission_queue.badge').set(#items)
    cb(vim.tbl_filter(function(i) return not walk.skipped[id_of(i)] end, items), #items)
  end)
end

local function finish(note)
  float.close()
  local o = walk.origin
  walk.origin, walk.skipped = nil, {}
  if o then origin.restore(o) end
  if note then vim.notify(note) end
end

local show_next

local function answer(item, behavior)
  if walk.busy then return end
  walk.busy = true
  rpc.resolve(item, behavior, function(ok, err)
    walk.busy = false
    if not ok then
      vim.notify(('permission queue: %s was already answered%s'):format(item.name,
        err and (' (' .. vim.trim(err) .. ')') or ''), vim.log.levels.WARN)
    end
    show_next()
  end)
end

show_next = function()
  load(function(items, total)
    if #items == 0 then
      return finish(total > 0 and (total .. ' skipped prompt(s) still waiting') or 'No permission prompts waiting')
    end
    local item = items[1]
    local pos = total - #items + 1
    local buf = float.show(item, pos, total, {
      a = function() answer(item, 'allow') end,
      d = function() answer(item, 'deny') end,
      s = function() walk.skipped[id_of(item)] = true; show_next() end,
      o = function() float.close(); rpc.open(item) end,
      g = function() float.close() end,
      q = function() finish() end,
    })
    rpc.tail(item, function(lines) float.set_message(buf, lines) end)
  end)
end

function M.open()
  if not walk.origin then walk.origin, walk.skipped = origin.save(), {} end
  show_next()
end

function M.setup(opts)
  vim.api.nvim_create_user_command('PermissionPrompts', M.open,
    { desc = 'Walk pending cc.nvim permission prompts in every Neovim' })
  if opts and opts.badge then require('permission_queue.badge').listen(load) end
end

return M
