-- Layout for the queue float: a title that fits (shrinking the agent name
-- first, never clipping the count), a height that counts wrapped rows, a
-- footer hint when the content scrolls, and treesitter highlighting for the
-- command or diff region.
local M = {}

--- `s` cut to `max` display cells with an ellipsis.
function M.truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then return s end
  if max <= 1 then return '…' end
  local out = vim.fn.strcharpart(s, 0, max - 1)
  while vim.fn.strdisplaywidth(out) > max - 1 do out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1) end
  return out .. '…'
end

--- " Permission 1 of 3 waiting · name (project) · 4m · deferred ", fitted.
function M.title(head, name, project, tail, width)
  local room = width - 4 - vim.fn.strdisplaywidth(head .. tail) - 6
  local where = project ~= '' and project or nil
  if where and room < vim.fn.strdisplaywidth(name) + vim.fn.strdisplaywidth(where) + 3 then
    where = nil -- drop the project before squeezing the name
  end
  local who = M.truncate(name, math.max(8, room - (where and (#where + 3) or 0)))
  if where then who = who .. ' (' .. where .. ')' end
  return M.truncate((' %s · %s%s '):format(head, who, tail), width - 2)
end

--- Screen rows `lines` take in a wrapping window `width` cells wide.
function M.rows(lines, width)
  local n = 0
  for _, l in ipairs(lines) do
    n = n + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  return n
end

--- Size and center the float to its content; hint when it scrolls.
function M.fit(win, buf, footer)
  if not vim.api.nvim_win_is_valid(win) then return end
  local cfg = vim.api.nvim_win_get_config(win)
  local max_h = math.max(6, math.floor(vim.o.lines * 0.75))
  local rows = M.rows(vim.api.nvim_buf_get_lines(buf, 0, -1, false), cfg.width)
  local height = math.max(4, math.min(rows, max_h))
  vim.api.nvim_win_set_config(win, {
    relative = 'editor', width = cfg.width, height = height,
    col = cfg.col, row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    footer = rows > height and (' ↓ more: j/k scroll ·' .. footer) or footer, footer_pos = 'center',
  })
end

local NS = vim.api.nvim_create_namespace('permission_queue_body')

--- Treesitter highlights for `lines` placed at buffer row `row0`.
function M.highlight(buf, row0, lines, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, table.concat(lines, '\n'), lang)
  if not ok or not parser then return end
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.get(lang, 'highlights')
  if not tree or not query then return end
  for id, node in query:iter_captures(tree:root(), table.concat(lines, '\n')) do
    local sr, sc, er, ec = node:range()
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, row0 + sr, sc, {
      end_row = row0 + er, end_col = ec, hl_group = '@' .. query.captures[id] .. '.' .. lang,
      priority = 100,
    })
  end
end

return M
