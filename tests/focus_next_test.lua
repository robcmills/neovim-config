-- Headless tests for agent priority rows in buffers.lua and :FocusNext.
--   nvim --headless --clean -l tests/focus_next_test.lua
local config = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(config)
vim.opt.runtimepath:append(vim.fn.expand('~/.local/share/nvim/site/pack/packer/start/nvim-web-devicons'))
package.path = config .. '/tests/?.lua;' .. package.path

local priority = require('agent_priority')
local fixture = require('fixtures.focus_next')
local data = vim.json.decode(table.concat(vim.fn.readfile(fixture.json), '\n'), { luanil = { object = true, array = true } })

local failures, count = 0, 0
local function test(name, fn)
  count = count + 1
  local ok, err = pcall(fn)
  if not ok then
    failures = failures + 1
    print('FAIL ' .. name .. ': ' .. tostring(err))
  else
    print('ok   ' .. name)
  end
end
local function eq(got, want)
  if not vim.deep_equal(got, want) then
    error(('\n  got:  %s\n  want: %s'):format(vim.inspect(got), vim.inspect(want)), 2)
  end
end

test('resolve: tagged session wins over cwd', function()
  eq({ priority.resolve(data, 's-tagged', '/tmp/fn/side') }, { 'high', 1 })
end)
test('resolve: null-bucket tag falls through to cwd', function()
  eq({ priority.resolve(data, 's-untagged', '/tmp/fn/side/x') }, { 'low', 6 })
end)
test('resolve: longest dir prefix (trailing slash ignored)', function()
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim/lua/cc') }, { 'low', 5 })
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim/lua') }, { 'low', 5 })
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim') }, { 'medium', 3 })
end)
test('resolve: prefix match is on path boundaries', function()
  eq({ priority.resolve(data, nil, '/tmp/fn/nvimx') }, { 'unknown', nil })
end)
test('resolve: store root and below never match a project', function()
  eq({ priority.resolve(data, nil, '/Users/robcmills/jarvis') }, { 'unknown', nil })
  eq({ priority.resolve(data, vim.NIL, '/Users/robcmills/jarvis/projects/') }, { 'unknown', nil })
  eq({ priority.resolve(data, nil, '/Users/robcmills/src') }, { 'high', 1 })
end)
test('resolve: no data or no match is unknown', function()
  eq({ priority.resolve(nil, 's-tagged', '/tmp/fn/voice') }, { 'unknown', nil })
  eq({ priority.resolve(data, nil, '/elsewhere') }, { 'unknown', nil })
  eq({ priority.resolve(data, nil, '') }, { 'unknown', nil })
end)

test('pick_unread: bucket, then effective, then oldest', function()
  local insts = {
    { outputBufnr = 1, state = 'unread', cwd = '/tmp/fn/voice', lastModifiedAt = 50 },
    { outputBufnr = 2, state = 'unread', cwd = '/tmp/fn/delivery', lastModifiedAt = 300 },
    { outputBufnr = 3, state = 'unread', cwd = '/tmp/fn/delivery', lastModifiedAt = 200 },
    { outputBufnr = 4, state = 'waiting', cwd = '/tmp/fn/delivery', lastModifiedAt = 1 },
    { outputBufnr = 5, state = 'unread', cwd = '/elsewhere', lastModifiedAt = 1 },
  }
  eq(priority.pick_unread(insts, data).outputBufnr, 3)
  eq(priority.pick_unread({ insts[1], insts[5] }, data).outputBufnr, 1)
  eq(priority.pick_unread({ insts[4] }, data), nil)
  -- With no priorities, all are unknown: the oldest wins
  eq(priority.pick_unread(insts, false).outputBufnr, 5)
end)

-- The sidebar, end to end, against the fixture
local buffers = require('buffers')
buffers.setup({
  format_file_name = function(_, name)
    name = name:gsub('^cc%-', '')
    local ts, rest = name:match('^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%-)(.*)')
    return ts and (ts .. '\n' .. rest) or name
  end,
})
fixture.load()
buffers.show('left')
priority.wait(2000)
vim.cmd('wincmd l')

local function rows()
  local out = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, -1, false)) do
    if line:match('^%S') then
      table.insert(out, line)
    end
  end
  return out
end
local function names()
  local out = {}
  local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match('^%S') then
      local rest = lines[i + 1]
      table.insert(out, rest and not rest:match('^%S') and vim.trim(rest) or line:match('^%S+%s+%S+%s+(.-)%s*$'))
    end
  end
  return out
end

test('sidebar: agents sorted by bucket and effective, ties stable, then files', function()
  local n = names()
  eq({ unpack(n, 1, 11) }, {
    'estimation-publish', 'standup-for-delivery', 'a-very-long-session-name-that-wraps-in-the-sidebar', -- high 1
    'wake-model', 'stopping', -- high 2
    'colemak-visual-mode', 'new-chat', -- medium 3
    'sidebar-worker', 'side-project', -- low 5, low 6
    'misc-question', 'store-cleanup', -- unknown
  })
  eq({ unpack(n, 12) }, { '[No Name]', 'init.lua', 'buffers.lua', 'agent_priority.lua', 'README.md' })
end)

test('sidebar: names start in the same display column on every line', function()
  local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, -1, false)
  local cols = {}
  for _, line in ipairs(lines) do
    local text = line:match('^%S') and line:match('^%S+%s+%S+%s+()') or line:match('^%s+()')
    cols[vim.fn.strdisplaywidth(line:sub(1, text - 1))] = true
  end
  eq(vim.tbl_keys(cols), { 5 })
end)

test('sidebar: agent rows carry the status emoji, no devicon, no name prefix', function()
  local r = rows()
  eq(r[1]:match('^%S+ (%S+)'), '🚧')
  eq(r[2]:match('^%S+ (%S+)'), '📬')
  eq(vim.fn.strdisplaywidth(r[1]), vim.fn.strdisplaywidth('a 🚧 2026-10-15T09:01:00-'))
end)

local function hl_at(line, col)
  local buf = vim.fn.bufnr('VerticalBuffersList')
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { line, 0 }, { line, -1 }, { details = true })) do
    if m[3] <= col and col < m[4].end_col then
      if m[4].hl_group:match('^BuffersPriority') or m[4].hl_group:match('^Buffers') then
        return m[4].hl_group
      end
    end
  end
end

test('sidebar: names colored by bucket, the current one bold', function()
  local first = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, 1, false)[1]
  local col = #first - 1
  eq(hl_at(0, col), 'BuffersPriorityHigh')
  local inst = fixture.by_name('colemak')
  vim.api.nvim_set_current_buf(inst.outputBufnr)
  local line = vim.api.nvim_win_get_cursor(vim.fn.win_findbuf(vim.fn.bufnr('VerticalBuffersList'))[1])[1]
  local text = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), line - 1, line, false)[1]
  eq(hl_at(line - 1, #text - 1), 'BuffersPriorityMediumCurrent')
  eq(vim.api.nvim_get_hl(0, { name = 'BuffersPriorityMediumCurrent' }).bold, true)
end)

local function cursor_buf()
  local win = vim.fn.win_findbuf(vim.fn.bufnr('VerticalBuffersList'))[1]
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return line
end

test('FocusNext: picks the tagged high-1 session, then high 2, then low, then nothing', function()
  local order = {}
  for _ = 1, 3 do
    vim.cmd('FocusNext')
    local inst
    for _, i in ipairs(fixture.instances) do
      if i.outputBufnr == vim.api.nvim_get_current_buf() then inst = i end
    end
    table.insert(order, inst and inst.name:match('%d%d%-(%a[%w-]*)$') or '?')
    -- Sidebar cursor sits on the current buffer's first row
    local sidebar = vim.fn.bufnr('VerticalBuffersList')
    local text = vim.api.nvim_buf_get_lines(sidebar, cursor_buf() - 1, cursor_buf() + 1, false)
    assert(table.concat(text, ' '):find(inst.name:sub(21), 1, true), 'cursor not on current row: ' .. vim.inspect(text))
    vim.wait(50)
  end
  eq(order, { 'standup-for-delivery', 'wake-model', 'side-project' })
  local before = vim.api.nvim_get_current_buf()
  local notes = {}
  local notify = vim.notify
  vim.notify = function(msg) table.insert(notes, msg) end
  vim.cmd('FocusNext')
  vim.notify = notify
  eq(notes, { 'Nothing unread' })
  eq(vim.api.nvim_get_current_buf(), before)
end)

test('failing priorities command: every agent is unknown, nothing errors', function()
  priority.setup({ cmd = { 'false' } })
  priority.refresh()
  priority.wait(2000)
  eq(priority.data(), nil)
  local buf = vim.fn.bufnr('VerticalBuffersList')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
  eq(hl_at(0, #lines[1] - 1):match('^BuffersPriorityUnknown') ~= nil, true)
  priority.setup({ cmd = { 'cat', fixture.json } })
  priority.refresh()
  priority.wait(2000)
end)

test('movePrev/moveNext: files reorder, agents only among equal priority', function()
  local file = vim.fn.bufnr(vim.fn.expand('~/.config/nvim/lua/buffers.lua'))
  vim.api.nvim_set_current_buf(file)
  buffers.movePrev()
  eq(names()[13], 'buffers.lua')
  buffers.movePrev() -- now the first file: it never moves into the agents
  buffers.movePrev()
  eq({ unpack(names(), 11, 13) }, { 'store-cleanup', 'buffers.lua', '[No Name]' })
  buffers.moveNext()
  eq({ unpack(names(), 12, 13) }, { '[No Name]', 'buffers.lua' })
  -- Equal-priority agents swap; across a bucket boundary nothing moves
  vim.api.nvim_set_current_buf(fixture.by_name('stopping').outputBufnr)
  buffers.movePrev()
  eq({ unpack(names(), 4, 5) }, { 'stopping', 'wake-model' })
  buffers.movePrev()
  eq({ unpack(names(), 3, 5) }, { 'a-very-long-session-name-that-wraps-in-the-sidebar', 'stopping', 'wake-model' })
end)

test('refresh coalesces a burst into one fetch', function()
  local calls = 0
  local system = vim.system
  vim.system = function(...) calls = calls + 1 return system(...) end
  for _ = 1, 10 do vim.api.nvim_exec_autocmds('User', { pattern = 'CcStateChanged' }) end
  priority.wait(2000)
  vim.system = system
  eq(calls, 1)
end)

print(('%d/%d passed'):format(count - failures, count))
vim.cmd(failures == 0 and 'qa!' or 'cq!')
