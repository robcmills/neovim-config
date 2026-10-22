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

test("resolve: a tag's effective priority wins over cwd", function()
  eq({ priority.resolve(data, 's-tagged', '/tmp/fn/side') }, { 1, 1 })
  eq({ priority.resolve(data, 's-medium', '/Users/robcmills/jarvis') }, { 3, 3 })
end)
test('resolve: a tag with no effective priority falls through to cwd', function()
  eq({ priority.resolve(data, 's-untagged', '/tmp/fn/side/x') }, { 5, 6 })
end)
test('resolve: level is the effective priority, 5 and up sharing level 5', function()
  eq({ priority.resolve(data, 'x', '/tmp/fn/infra') }, { 4, 4 })
  eq({ priority.resolve(data, 'x', '/tmp/fn/archive/2025') }, { 5, 12 })
end)
test('resolve: longest dir prefix (trailing slash ignored)', function()
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim/lua/cc') }, { 5, 5 })
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim/lua') }, { 5, 5 })
  eq({ priority.resolve(data, 'x', '/tmp/fn/nvim') }, { 3, 3 })
end)
test('resolve: prefix match is on path boundaries', function()
  eq({ priority.resolve(data, nil, '/tmp/fn/nvimx') }, {})
end)
test('resolve: store root and below never match a project', function()
  eq({ priority.resolve(data, nil, '/Users/robcmills/jarvis') }, {})
  eq({ priority.resolve(data, vim.NIL, '/Users/robcmills/jarvis/projects/') }, {})
  eq({ priority.resolve(data, nil, '/Users/robcmills/src') }, { 1, 1 })
end)
test('resolve: no data or no match is unknown', function()
  eq({ priority.resolve(nil, 's-tagged', '/tmp/fn/voice') }, {})
  eq({ priority.resolve(data, nil, '/elsewhere') }, {})
  eq({ priority.resolve(data, nil, '') }, {})
end)

test('pick_unread: level, then effective, then oldest', function()
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
    return (name:gsub('^cc%-', ''))
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
  eq({ unpack(n, 1, 14) }, {
    'estimation-publish', 'standup-for-delivery', 'a-very-long-session-name-that-clips-in-the-sidebar', -- 1
    'voice-workflow-hud', 'interrupt-retry', -- 2
    'colemak-visual-mode', 'nvim-output', 'cy-quote-review', -- 3 (cy: tagged 3)
    'infra-terraform-plan', -- 4
    'sidebar-worker', 'browserslist-impl', 'old-archive-notes', -- 5, 6, 12 (level 5)
    'manual-picks-no-match', 'store-cleanup', -- unknown
  })
  eq({ unpack(n, 15) }, { '[No Name]', 'init.lua', 'buffers.lua', 'agent_priority.lua', 'README.md' })
end)

test('sidebar: names start in the same display column on every line', function()
  local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, -1, false)
  local cols = {}
  for _, line in ipairs(lines) do
    local text = line:match('^%S') and line:match('^%S+%s+%S+%s+()') or line:match('^%s+()')
    cols[vim.fn.strdisplaywidth(line:sub(1, text - 1))] = true
  end
  eq(vim.tbl_keys(cols), { 4 })
end)

test('sidebar: agent rows carry a colored one-cell status icon, no devicon, no name prefix', function()
  local r = rows()
  eq(r[1]:match('^%S+ (%S+)'), '󱌢')
  eq(r[2]:match('^%S+ (%S+)'), '󰇮')
  eq(vim.fn.strdisplaywidth(r[1]), vim.fn.strdisplaywidth('a x estimation-publish'))
  local buf = vim.fn.bufnr('VerticalBuffersList')
  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { 0, 2 }, { 0, 2 }, { details = true })
  eq(vim.tbl_contains(vim.tbl_map(function(m) return m[4].hl_group end, marks), 'BuffersStatus_working'), true)
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

test('sidebar: names colored by level; only the current one white and bold', function()
  local first = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), 0, 1, false)[1]
  local col = #first - 1
  eq(hl_at(0, col), 'BuffersPriority1')
  local inst = fixture.by_name('colemak')
  vim.api.nvim_set_current_buf(inst.outputBufnr)
  local line = vim.api.nvim_win_get_cursor(vim.fn.win_findbuf(vim.fn.bufnr('VerticalBuffersList'))[1])[1]
  local text = vim.api.nvim_buf_get_lines(vim.fn.bufnr('VerticalBuffersList'), line - 1, line, false)[1]
  eq(hl_at(line - 1, #text - 1), 'BuffersPriorityCurrent')
  local current = vim.api.nvim_get_hl(0, { name = 'BuffersPriorityCurrent' })
  eq({ current.fg, current.bold }, { 0xffffff, true })
  for level = 1, priority.LEVELS do
    assert(vim.api.nvim_get_hl(0, { name = 'BuffersPriority' .. level }).fg ~= 0xffffff, 'level ' .. level .. ' is pure white')
  end
end)

local function cursor_buf()
  local win = vim.fn.win_findbuf(vim.fn.bufnr('VerticalBuffersList'))[1]
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return line
end

test('FocusNext: unread by level, then cycle the ready rows', function()
  local order = {}
  for _ = 1, 5 do
    vim.cmd('FocusNext')
    local inst
    for _, i in ipairs(fixture.instances) do
      if i.outputBufnr == vim.api.nvim_get_current_buf() then inst = i end
    end
    table.insert(order, inst and inst.name or '?')
    -- Sidebar cursor sits on the current buffer's first row
    local sidebar = vim.fn.bufnr('VerticalBuffersList')
    local text = vim.api.nvim_buf_get_lines(sidebar, cursor_buf() - 1, cursor_buf() + 1, false)
    assert(text[1]:find(inst.name, 1, true), 'cursor not on current row: ' .. vim.inspect(text))
    vim.wait(50)
  end
  eq(order, { 'standup-for-delivery', 'voice-workflow-hud', 'cy-quote-review', 'infra-terraform-plan', 'browserslist-impl' })
  local notes = {}
  local notify = vim.notify
  vim.notify = function(msg) table.insert(notes, msg) end
  -- Nothing unread: cycle the ready rows in sidebar order, wrapping
  local function current_name()
    for _, i in ipairs(fixture.instances) do
      if i.outputBufnr == vim.api.nvim_get_current_buf() or i.promptBufnr == vim.api.nvim_get_current_buf() then
        return i.name
      end
    end
  end
  local ready = {}
  for _, row in ipairs(names()) do
    local inst = fixture.by_name(row)
    if inst and inst.state == 'ready' then table.insert(ready, inst.name) end
  end
  eq(#ready, 7)
  -- From a non-ready row: the first ready row
  vim.api.nvim_set_current_buf(fixture.by_name('estimation-publish').outputBufnr)
  local cycle = {}
  for _ = 1, #ready + 1 do
    vim.cmd('FocusNext')
    table.insert(cycle, current_name())
  end
  eq(cycle, vim.list_extend(vim.deepcopy(ready), { ready[1] }))
  eq(notes[1], 'Nothing unread; ready 1/7')
  eq(notes[#ready + 1], 'Nothing unread; ready 1/7')
  -- From a ready agent's prompt buffer, its row counts as current
  vim.api.nvim_set_current_buf(fixture.by_name(ready[3]).promptBufnr)
  vim.cmd('FocusNext')
  eq(current_name(), ready[4])
  -- An agent turning unread mid-cycle comes first, then the cycle resumes below it
  fixture.by_name(ready[6]).state = 'unread'
  vim.cmd('FocusNext')
  eq(current_name(), ready[6])
  vim.cmd('FocusNext')
  eq(current_name(), ready[7])
  -- One ready agent, already on it: stay and say so
  local saved = {}
  for _, i in ipairs(fixture.instances) do
    saved[i] = i.state
    if i.state == 'ready' and i.name ~= ready[7] then i.state = 'working' end
  end
  vim.cmd('FocusNext')
  eq(notes[#notes], 'Nothing unread; the only ready agent')
  eq(current_name(), ready[7])
  -- No ready agents
  for i in pairs(saved) do if i.state == 'ready' then i.state = 'working' end end
  vim.cmd('FocusNext')
  eq(notes[#notes], 'Nothing unread or ready')
  eq(current_name(), ready[7])
  for i, st in pairs(saved) do i.state = st end
  -- No agents at all
  local instances = fixture.instances
  fixture.instances = {}
  local before = vim.api.nvim_get_current_buf()
  vim.cmd('FocusNext')
  fixture.instances = instances
  vim.notify = notify
  eq(notes[#notes], 'Nothing unread or ready')
  eq(vim.api.nvim_get_current_buf(), before)
end)

test('failing priorities command: every agent is unknown, nothing errors', function()
  vim.api.nvim_set_current_buf(vim.fn.bufnr(vim.fn.expand('~/.config/nvim/init.lua')))
  priority.setup({ cmd = { 'false' } })
  priority.refresh()
  priority.wait(2000)
  eq(priority.data(), nil)
  local buf = vim.fn.bufnr('VerticalBuffersList')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
  eq(hl_at(0, #lines[1] - 1), 'BuffersPriorityUnknown')
  priority.setup({ cmd = { 'cat', fixture.json } })
  priority.refresh()
  priority.wait(2000)
end)

test('movePrev/moveNext: files reorder, agents only among equal priority', function()
  local file = vim.fn.bufnr(vim.fn.expand('~/.config/nvim/lua/buffers.lua'))
  vim.api.nvim_set_current_buf(file)
  buffers.movePrev()
  eq(names()[16], 'buffers.lua')
  buffers.movePrev() -- now the first file: it never moves into the agents
  buffers.movePrev()
  eq({ unpack(names(), 14, 16) }, { 'store-cleanup', 'buffers.lua', '[No Name]' })
  buffers.moveNext()
  eq({ unpack(names(), 15, 16) }, { '[No Name]', 'buffers.lua' })
  -- Equal-priority agents swap; across a bucket boundary nothing moves
  vim.api.nvim_set_current_buf(fixture.by_name('interrupt-retry').outputBufnr)
  buffers.movePrev()
  eq({ unpack(names(), 4, 5) }, { 'interrupt-retry', 'voice-workflow-hud' })
  buffers.movePrev()
  eq({ unpack(names(), 3, 5) }, { 'a-very-long-session-name-that-clips-in-the-sidebar', 'interrupt-retry', 'voice-workflow-hud' })
end)

test('no other buffer opens in the sidebar window', function()
  local sidebar = vim.fn.bufnr('VerticalBuffersList')
  local win = vim.fn.win_findbuf(sidebar)[1]
  local ok, err = pcall(vim.api.nvim_win_set_buf, win, vim.fn.bufnr(vim.fn.expand('~/.config/nvim/init.lua')))
  eq(ok, false)
  assert(tostring(err):find('E1513', 1, true), err)
  eq(vim.api.nvim_win_get_buf(win), sidebar)
end)

test('another buffer loaded into the sidebar window: no render errors, BuffersShow reopens', function()
  local sidebar = vim.fn.bufnr('VerticalBuffersList')
  vim.api.nvim_set_current_win(vim.fn.win_findbuf(sidebar)[1])
  -- With 'winfixbuf' turned off, what cc.nvim did when a session opened with
  -- the sidebar focused: stage a one-line buffer in the current window, then
  -- enter the session's output
  vim.wo.winfixbuf = false
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(scratch)
  local inst = fixture.by_name('colemak')
  vim.api.nvim_set_current_buf(inst.outputBufnr)
  eq(vim.fn.win_findbuf(sidebar), {})
  vim.cmd('BuffersShow')
  eq(#vim.fn.win_findbuf(sidebar), 1)
  vim.cmd('wincmd p')
  eq(vim.api.nvim_get_current_buf(), inst.outputBufnr)
  local text = vim.api.nvim_buf_get_lines(sidebar, cursor_buf() - 1, cursor_buf(), false)
  assert(text[1]:find(inst.name, 1, true), 'cursor not on current row: ' .. vim.inspect(text))
  vim.api.nvim_buf_delete(scratch, { force = true })
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

test('priority_colors overrides a level color', function()
  buffers.setup({ priority_colors = { [3] = '#123456' } })
  eq(vim.api.nvim_get_hl(0, { name = 'BuffersPriority3' }).fg, 0x123456)
  eq(vim.api.nvim_get_hl(0, { name = 'BuffersPriority2' }).fg, tonumber(buffers.PRIORITY_COLORS[2]:sub(2), 16))
  buffers.setup({ priority_colors = {} })
end)

print(('%d/%d passed'):format(count - failures, count))
vim.cmd(failures == 0 and 'qa!' or 'cq!')
