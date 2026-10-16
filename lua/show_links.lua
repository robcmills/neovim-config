-- Link targets (urls, Jira keys, PR refs) for `gu` and :ShowLinks.
--
-- :ShowLinks labels every target visible in the cc.nvim output window (or
-- the current window) with a letter, Homerow style, then waits for one key:
-- a label opens its target in Brave, anything else cancels. The command
-- returns before waiting, so it is safe to call over RPC.

local M = {}

M.PATTERNS = {
  url = [=[\vhttps?://[^[:space:]<>"'`)\]]+]=],
  jira = [=[\v<[A-Z][A-Z0-9]+-\d+>]=],
  pr = [=[\v\c<%(PR|pull request)>\s*#?\d+|#\d+]=],
}
-- Earlier kinds win when matches overlap: a Jira key or #N inside a url is
-- part of the url.
M.KINDS = { 'url', 'jira', 'pr' }
M.LABELS = 'abcdefghijklmnopqrstuvwxyz'

local ns = vim.api.nvim_create_namespace('show_links')

---@param kind 'url'|'jira'|'pr'
---@param text string the matched text
---@return string
function M.resolve(kind, text)
  if kind == 'url' then
    return (text:gsub('[.,;:]+$', ''))
  elseif kind == 'jira' then
    return 'https://openspaceai.atlassian.net/browse/' .. text
  end
  return 'https://github.com/openspacelabs/openspace/pull/' .. text:match('%d+$')
end

-- Every match of `pattern` in `line`: { text, s, e } with 0-based byte
-- columns, `e` exclusive.
local function matches(line, pattern)
  local out, start = {}, 0
  while true do
    local text, s, e = unpack(vim.fn.matchstrpos(line, pattern, start))
    if s == -1 then return out end
    table.insert(out, { text, s, e })
    start = e
  end
end

-- The url under the cursor, or nil. Same precedence as `find`: a url, then
-- a Jira key, then a PR ref.
function M.under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col('.')
  for _, kind in ipairs(M.KINDS) do
    for _, m in ipairs(matches(line, M.PATTERNS[kind])) do
      if col > m[2] and col <= m[3] then
        return M.resolve(kind, m[1])
      end
    end
  end
end

-- Every target in `line`, left to right, none overlapping.
---@return { kind: string, text: string, s: integer, e: integer, url: string }[]
function M.find(line)
  local found = {}
  for _, kind in ipairs(M.KINDS) do
    for _, m in ipairs(matches(line, M.PATTERNS[kind])) do
      local s, e = m[2], m[3]
      local free = true
      for _, t in ipairs(found) do
        if s < t.e and t.s < e then free = false break end
      end
      if free then
        local url = M.resolve(kind, m[1])
        -- A url's trailing punctuation is not highlighted
        if kind == 'url' then e = s + #url end
        table.insert(found, { kind = kind, text = m[1], s = s, e = m[3], hl_e = e, url = url })
      end
    end
  end
  table.sort(found, function(a, b) return a.s < b.s end)
  return found
end

function M.open(url)
  vim.fn.jobstart({ 'open', '-a', 'Brave Browser', url }, { detach = true })
end

-- The cc.nvim output window in the current tab: the current instance's if
-- the cursor is in its output or prompt, else the first one. Falls back to
-- the current window.
function M.target_window()
  local cur = vim.api.nvim_get_current_win()
  local ok, cc = pcall(require, 'cc')
  local insts = ok and type(cc.list_instances) == 'function' and cc.list_instances() or {}
  local outputs, mine = {}, nil
  local curbuf = vim.api.nvim_get_current_buf()
  for _, inst in ipairs(insts) do
    outputs[inst.outputBufnr] = true
    if curbuf == inst.outputBufnr or curbuf == inst.promptBufnr then
      mine = inst.outputBufnr
    end
  end
  local first
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == mine then return win end
    if outputs[buf] and not first then first = win end
  end
  return first or cur
end

-- Targets on the lines visible in `win`, in reading order. Lines inside a
-- closed fold are hidden, so skipped.
function M.scan(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local targets = {}
  vim.api.nvim_win_call(win, function()
    local lnum, last = vim.fn.line('w0'), vim.fn.line('w$')
    while lnum <= last do
      local fold_end = vim.fn.foldclosedend(lnum)
      if fold_end ~= -1 then
        lnum = fold_end + 1
      else
        local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
        for _, t in ipairs(M.find(line)) do
          t.lnum = lnum
          table.insert(targets, t)
        end
        lnum = lnum + 1
      end
    end
  end)
  return targets
end

local active -- { buf, targets } while labels are shown
local waiting = false -- a scheduled getcharstr is pending or blocking

function M.clear()
  if active and vim.api.nvim_buf_is_valid(active.buf) then
    vim.api.nvim_buf_clear_namespace(active.buf, ns, 0, -1)
  end
  active = nil
end

-- Place labels on up to 26 targets in `win`. Returns them, label set.
function M.label(win)
  M.clear()
  local buf = vim.api.nvim_win_get_buf(win)
  local targets = M.scan(win)
  local labeled = {}
  for i, t in ipairs(targets) do
    if i > #M.LABELS then break end
    t.label = M.LABELS:sub(i, i)
    vim.api.nvim_buf_set_extmark(buf, ns, t.lnum - 1, t.s, {
      -- A space between label and link, so the label never reads as part of it
      virt_text = { { t.label, 'ShowLinksLabel' }, { ' ' } },
      virt_text_pos = 'inline',
      priority = 1000,
    })
    vim.api.nvim_buf_set_extmark(buf, ns, t.lnum - 1, t.s, {
      end_col = t.hl_e,
      hl_group = 'ShowLinksMatch',
      priority = 1000,
    })
    table.insert(labeled, t)
  end
  if #labeled > 0 then
    active = { buf = buf, targets = labeled }
  end
  return labeled
end

-- Open the target labeled `key` if there is one. Clears labels either way.
function M.select(key)
  local targets = active and active.targets or {}
  M.clear()
  for _, t in ipairs(targets) do
    if t.label == key then
      M.open(t.url)
      return t
    end
  end
end

function M.show()
  local labeled = M.label(M.target_window())
  if #labeled == 0 then
    vim.notify('No links on screen')
    return
  end
  -- Wait outside the command, so an RPC caller is not blocked. A second
  -- :ShowLinks while waiting relabels; the pending wait serves it.
  if waiting then return end
  waiting = true
  vim.schedule(function()
    vim.cmd.redraw()
    local ok, key = pcall(vim.fn.getcharstr)
    waiting = false
    if active then
      M.select(ok and key or nil)
      vim.cmd.redraw()
    end
  end)
end

local function set_highlights()
  local ok, c = pcall(require, 'colors')
  if not ok or type(c) ~= 'table' then c = {} end
  vim.api.nvim_set_hl(0, 'ShowLinksLabel', {
    default = true, bold = true, fg = c.black or '#15161e', bg = c.orange or '#ff9e64',
  })
  vim.api.nvim_set_hl(0, 'ShowLinksMatch', {
    default = true, underline = true, fg = c.cyan or '#7dcfff',
  })
end

function M.setup()
  set_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('show_links', { clear = true }),
    callback = set_highlights,
  })
  vim.api.nvim_create_user_command('ShowLinks', M.show, { desc = 'Label links on screen; a label key opens one in Brave' })
  vim.keymap.set('n', 'gl', M.show, { desc = 'Label links on screen (ShowLinks)' })
  vim.keymap.set('n', 'gu', function()
    local url = M.under_cursor()
    if not url then
      vim.notify('No url, Jira key, or PR number under cursor', vim.log.levels.WARN)
      return
    end
    M.open(url)
  end, { desc = 'Open url under cursor in Brave' })
end

return M
