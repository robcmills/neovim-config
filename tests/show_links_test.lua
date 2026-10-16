-- Headless tests for show_links.lua (`gu` and :ShowLinks).
--   nvim --headless --clean -l tests/show_links_test.lua
local config = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(config)

local sl = require('show_links')
sl.setup()
local opened = {}
sl.open = function(url) table.insert(opened, url) end

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

local function urls(line)
  return vim.tbl_map(function(t) return t.url end, sl.find(line))
end

test('find: urls, Jira keys and PR refs, left to right', function()
  eq(urls('See RAD-1234 and #12345, PR 678, pull request #9 at https://example.com/a.'), {
    'https://openspaceai.atlassian.net/browse/RAD-1234',
    'https://github.com/openspacelabs/openspace/pull/12345',
    'https://github.com/openspacelabs/openspace/pull/678',
    'https://github.com/openspacelabs/openspace/pull/9',
    'https://example.com/a',
  })
end)
test('find: a Jira key or #N inside a url is part of the url', function()
  eq(urls('https://openspaceai.atlassian.net/browse/RAD-99 and https://github.com/o/r/pull/5#issuecomment-7'), {
    'https://openspaceai.atlassian.net/browse/RAD-99',
    'https://github.com/o/r/pull/5#issuecomment-7',
  })
end)
test('find: not links', function()
  eq(urls('rad-12, R-1x, word PRs 12, ftp://x, nothing'), {})
end)
test('find: the url highlight stops before trailing punctuation', function()
  local t = sl.find('go https://x.io/a;. now')[1]
  eq({ t.s, t.hl_e, t.e }, { 3, 17, 19 })
end)

-- `gu` as it was before the refactor, for parity
local function old_gu(line, col)
  local function match_under_cursor(pattern)
    local start = 0
    while true do
      local match, s, e = unpack(vim.fn.matchstrpos(line, pattern, start))
      if s == -1 then return nil end
      if col > s and col <= e then return match end
      start = e
    end
  end
  local url = match_under_cursor([=[\vhttps?://[^[:space:]<>"'`)\]]+]=])
  if url then url = url:gsub('[.,;:]+$', '') end
  if not url then
    local key = match_under_cursor([=[\v<[A-Z][A-Z0-9]+-\d+>]=])
    if key then url = 'https://openspaceai.atlassian.net/browse/' .. key end
  end
  if not url then
    local ref = match_under_cursor([=[\v\c<%(PR|pull request)>\s*#?\d+|#\d+]=])
    if ref then url = 'https://github.com/openspacelabs/openspace/pull/' .. ref:match('%d+$') end
  end
  return url
end

test('gu: same result as before at every cursor column', function()
  local lines = {
    'See RAD-1234 and #12345, PR 678, pull request #9 at https://example.com/a.',
    'https://openspaceai.atlassian.net/browse/RAD-99 (https://github.com/o/r/pull/5#c-7) pr #3',
    'nothing here, AB-1x, #, PR, `RAD-5`',
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for lnum, line in ipairs(lines) do
    for col = 0, #line - 1 do
      vim.api.nvim_win_set_cursor(0, { lnum, col })
      eq(sl.under_cursor(), old_gu(line, col + 1))
    end
  end
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  opened = {}
  vim.cmd('normal gu')
  eq(opened, { 'https://openspaceai.atlassian.net/browse/RAD-1234' })
end)

-- A cc.nvim stand-in: one instance, output above prompt
local function cc_layout(lines)
  vim.cmd('silent! only')
  local out = vim.api.nvim_create_buf(true, true)
  local prompt = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(out, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(out)
  local out_win = vim.api.nvim_get_current_win()
  vim.cmd('belowright 3split')
  vim.api.nvim_set_current_buf(prompt)
  package.loaded.cc = {
    list_instances = function() return { { outputBufnr = out, promptBufnr = prompt } } end,
  }
  return out, prompt, out_win
end

test('target window: the output window, even from the prompt', function()
  local _, _, out_win = cc_layout({ 'x' })
  eq(sl.target_window(), out_win)
  vim.cmd('wincmd k')
  eq(sl.target_window(), out_win)
  vim.cmd('wincmd j')
  vim.cmd('vsplit')
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
  eq(sl.target_window(), out_win)
end)
test('target window: the current window with no cc output in the tab', function()
  cc_layout({ 'x' })
  vim.cmd('tabnew')
  eq(sl.target_window(), vim.api.nvim_get_current_win())
  package.loaded.cc = nil
  eq(sl.target_window(), vim.api.nvim_get_current_win())
  vim.cmd('tabclose')
end)

local function marks(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text then
      table.insert(out, { m[2] + 1, m[3], d.virt_text[1][1], d.virt_text_pos })
    end
  end
  return out
end

test('labels: visible lines only, reading order, before each match', function()
  local lines = {}
  for i = 1, 60 do lines[i] = ('line %d RAD-%d'):format(i, i) end
  lines[3] = 'two: #11 and https://a.io/x#RAD-1'
  local out, _, out_win = cc_layout(lines)
  vim.api.nvim_win_set_height(out_win, 10)
  vim.api.nvim_win_call(out_win, function() vim.cmd('normal! gg') end)
  local labeled = sl.label(out_win)
  eq(#labeled, 11) -- lines 1..10, line 3 has two
  local m = marks(out)
  eq({ m[1], m[3], m[4], m[11] }, {
    { 1, 7, 'a', 'inline' }, { 3, 5, 'c', 'inline' }, { 3, 13, 'd', 'inline' }, { 10, 8, 'k', 'inline' },
  })
  eq(labeled[4].url, 'https://a.io/x#RAD-1')
  sl.clear()
  eq(marks(out), {})
end)
test('labels: own cells left of the link, a space between, wide chars and column 0', function()
  local out, _, out_win = cc_layout({ 'https://a.io x', '日本 RAD-1 é #2' })
  vim.api.nvim_win_call(out_win, function() vim.wo.number = false end)
  sl.label(out_win)
  vim.cmd('redraw')
  local pos = vim.fn.win_screenpos(out_win)
  local function cells(r, n)
    local t = {}
    for c = 0, n - 1 do t[#t + 1] = vim.fn.screenstring(pos[1] + r, pos[2] + c) end
    return t
  end
  eq(cells(0, 9), { 'a', ' ', 'h', 't', 't', 'p', 's', ':', '/' })
  eq(cells(1, 16), { '日', '', '本', '', ' ', 'b', ' ', 'R', 'A', 'D', '-', '1', ' ', 'é', ' ', 'c' })
  eq(cells(1, 19)[17], ' ')
  eq(cells(1, 19)[18], '#')
  sl.clear()
end)
test('labels: closed folds hide their links', function()
  local lines = {}
  for i = 1, 8 do lines[i] = ('RAD-%d'):format(i) end
  local out, _, out_win = cc_layout(lines)
  vim.api.nvim_win_call(out_win, function()
    vim.wo.foldmethod = 'manual'
    vim.cmd('2,5fold')
  end)
  eq(vim.tbl_map(function(t) return t.text end, sl.label(out_win)), { 'RAD-1', 'RAD-6', 'RAD-7', 'RAD-8' })
  sl.clear()
  eq(#marks(out), 0)
end)
test('labels: stop at 26', function()
  local line = {}
  for i = 1, 40 do line[i] = '#' .. i end
  local out, _, out_win = cc_layout({ table.concat(line, ' ') })
  local labeled = sl.label(out_win)
  eq(#labeled, 26)
  eq({ labeled[1].label, labeled[26].label, labeled[26].text }, { 'a', 'z', '#26' })
  eq(#marks(out), 26)
  sl.clear()
end)

test('select: a label opens its target; anything else cancels; both clear', function()
  local out, _, out_win = cc_layout({ 'RAD-1 #2 https://b.io' })
  opened = {}
  sl.label(out_win)
  eq(sl.select('c').url, 'https://b.io')
  eq(opened, { 'https://b.io' })
  eq(#marks(out), 0)
  sl.label(out_win)
  eq(sl.select('q'), nil)
  sl.label(out_win)
  eq(sl.select('\27'), nil)
  eq(opened, { 'https://b.io' })
  eq(#marks(out), 0)
end)

test(':ShowLinks waits for a key after returning, then opens it', function()
  local out = cc_layout({ 'RAD-1 #2 https://b.io' })
  opened = {}
  vim.cmd('ShowLinks')
  eq(#marks(out), 3) -- labels are up before the wait starts
  vim.api.nvim_feedkeys('b', 't', false)
  vim.wait(500, function() return #opened > 0 end)
  eq(opened, { 'https://github.com/openspacelabs/openspace/pull/2' })
  eq(#marks(out), 0)
  -- Esc cancels
  vim.cmd('ShowLinks')
  vim.api.nvim_feedkeys('\27', 't', false)
  vim.wait(500, function() return #marks(out) == 0 end)
  eq({ #marks(out), #opened }, { 0, 1 })
end)

test(':ShowLinks with nothing on screen notifies', function()
  local out = cc_layout({ 'no links here' })
  local notes = {}
  local notify = vim.notify
  vim.notify = function(msg) table.insert(notes, msg) end
  vim.cmd('ShowLinks')
  vim.notify = notify
  eq(notes, { 'No links on screen' })
  eq(#marks(out), 0)
end)

test('highlights: legible label colors, user overrides survive setup', function()
  local label = vim.api.nvim_get_hl(0, { name = 'ShowLinksLabel' })
  assert(label.fg and label.bg and label.bold, vim.inspect(label))
  vim.api.nvim_set_hl(0, 'ShowLinksLabel', { fg = 0x123456 })
  sl.setup()
  eq(vim.api.nvim_get_hl(0, { name = 'ShowLinksLabel' }).fg, 0x123456)
end)

test('RPC: nvim_command ShowLinks returns at once; the next key opens', function()
  local chan = vim.fn.jobstart({ 'nvim', '--embed', '--headless', '--clean' }, { rpc = true })
  local function lua(code, ...) return vim.rpcrequest(chan, 'nvim_exec_lua', code, { ... }) end
  lua([[
    vim.opt.runtimepath:prepend(...)
    local sl = require('show_links')
    sl.setup()
    _G.opened = {}
    sl.open = function(url) table.insert(_G.opened, url) end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'RAD-7 and https://c.io' })
  ]], config)
  local start = vim.uv.hrtime()
  vim.rpcrequest(chan, 'nvim_command', 'ShowLinks')
  local ms = (vim.uv.hrtime() - start) / 1e6
  assert(ms < 200, ('took %d ms'):format(ms))
  -- The child is now blocked in getcharstr; requests still answer
  vim.wait(100)
  eq(lua([[return #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {})]]), 4)
  vim.rpcrequest(chan, 'nvim_input', 'b')
  vim.wait(1000, function() return #lua('return _G.opened') > 0 end)
  eq(lua('return _G.opened'), { 'https://c.io' })
  eq(lua([[return #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {})]]), 0)
  vim.fn.jobstop(chan)
end)

print(('%d/%d passed'):format(count - failures, count))
vim.cmd(failures == 0 and 'qa!' or 'cq!')
