-- Project priority for cc.nvim agent sessions, read from
-- `jarvis priorities --json` (see buffers.lua, which sorts and colors agent
-- rows by it, and :FocusNext).
--
-- The command runs asynchronously and its result is cached. Refreshes are
-- event-driven only (never a timer): a burst of requests in one tick runs
-- one fetch, and a request during a fetch runs one more after it. If the
-- command fails, the cache is nil and every session is "unknown".
--
-- A session resolves to its tagged bucket (`sessions[sessionId]`), else the
-- bucket of the project whose dir is the longest prefix of its cwd, else
-- "unknown". A cwd at or under the store root never matches a project.

local M = {}

M.BUCKETS = { "high", "medium", "low", "unknown" }
local RANK = { high = 1, medium = 2, low = 3, unknown = 4 }

local state = {
  cmd = { "jarvis", "priorities", "--json" },
  data = nil, -- last decoded result; nil until fetched or when the command fails
  fetched = false,
  queued = false, -- a fetch is scheduled for the end of this tick
  inflight = false,
  again = false, -- a refresh was requested during the fetch in flight
  on_change = nil,
}

---@param opts { cmd?: string[], on_change?: fun() }|nil
function M.setup(opts)
  opts = opts or {}
  if opts.cmd then
    state.cmd = opts.cmd
  end
  if opts.on_change then
    state.on_change = opts.on_change
  end
end

local function finish(data)
  local changed = not state.fetched or not vim.deep_equal(data, state.data)
  state.data, state.fetched, state.inflight = data, true, false
  if state.again then
    state.again = false
    M.refresh()
  end
  if changed and state.on_change then
    state.on_change()
  end
end

local function decode(res)
  if res.code ~= 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
  return ok and type(data) == "table" and data or nil
end

local function start()
  state.inflight = true
  local ok = pcall(vim.system, state.cmd, { text = true }, vim.schedule_wrap(function(res)
    finish(decode(res))
  end))
  if not ok then -- e.g. the executable is missing
    finish(nil)
  end
end

-- Ask for a fresh fetch. Calls in the same tick coalesce into one.
function M.refresh()
  if state.queued then
    return
  end
  state.queued = true
  vim.schedule(function()
    state.queued = false
    if state.inflight then
      state.again = true
    else
      start()
    end
  end)
end

-- Block up to `ms` for any queued or in-flight fetch to land.
function M.wait(ms)
  vim.wait(ms, function()
    return not (state.queued or state.inflight or state.again)
  end, 10)
end

function M.data()
  return state.data
end

-- Test hook: replace the cache as if a fetch returned `data`.
function M.set_data(data)
  state.data, state.fetched = data, true
end

local function strip(path)
  return (path:gsub("(.)/+$", "%1"))
end

local function under(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

---@return string bucket "high", "medium", "low" or "unknown"
---@return number|nil effective
function M.resolve(data, session_id, cwd)
  if not data then
    return "unknown", nil
  end
  local tagged = type(session_id) == "string" and data.sessions and data.sessions[session_id]
  if tagged and RANK[tagged.bucket] and tagged.bucket ~= "unknown" then
    return tagged.bucket, tagged.effective
  end
  if type(cwd) ~= "string" or cwd == "" then
    return "unknown", nil
  end
  cwd = strip(cwd)
  if type(data.storeRoot) == "string" and under(cwd, strip(data.storeRoot)) then
    return "unknown", nil
  end
  local best, best_len = nil, -1
  for _, project in ipairs(data.projects or {}) do
    for _, dir in ipairs(project.dirs or {}) do
      dir = strip(dir)
      if #dir > best_len and under(cwd, dir) then
        best, best_len = project, #dir
      end
    end
  end
  if best and RANK[best.bucket] then
    return best.bucket, best.effective
  end
  return "unknown", nil
end

-- Bucket and effective priority of a cc.nvim instance snapshot (list_instances)
function M.of(inst)
  return M.resolve(state.data, inst.sessionId, inst.cwd)
end

function M.rank(bucket)
  return RANK[bucket] or RANK.unknown
end

-- Sort key for an instance: bucket rank, then effective priority (unset last)
function M.key(bucket, effective)
  return { M.rank(bucket), type(effective) == "number" and effective or math.huge }
end

-- Compare two keys; returns nil on a tie so callers can break it themselves
function M.before(a, b)
  for i = 1, #a do
    if a[i] ~= b[i] then
      return a[i] < b[i]
    end
  end
  return nil
end

-- The unread instance to focus next: highest priority, then unread longest
-- (oldest lastModifiedAt), then lowest output bufnr. nil if none is unread.
function M.pick_unread(instances, data)
  if data == nil then
    data = state.data
  end
  local best, best_key
  for _, inst in ipairs(instances or {}) do
    if inst.state == "unread" then
      local bucket, effective = M.resolve(data, inst.sessionId, inst.cwd)
      local modified = type(inst.lastModifiedAt) == "number" and inst.lastModifiedAt or math.huge
      local key = M.key(bucket, effective)
      table.insert(key, modified)
      table.insert(key, inst.outputBufnr or math.huge)
      if not best_key or M.before(key, best_key) then
        best, best_key = inst, key
      end
    end
  end
  return best
end

return M
