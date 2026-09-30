-- nvim-treesitter `main` only installs parsers and queries and provides an
-- indentexpr. Highlighting and node selection come from Neovim itself.
local ts = require('nvim-treesitter')

-- jsonc files use the json parser on `main`; tmux was dropped upstream.
local parsers = {
  'bash', 'c', 'cpp', 'css', 'csv', 'diff', 'dockerfile', 'editorconfig',
  'gdscript', 'git_rebase', 'gitcommit', 'gitignore', 'glsl', 'go', 'html',
  'ini', 'java', 'javascript', 'json', 'kotlin', 'lua', 'make', 'markdown',
  'pem', 'prisma', 'properties', 'python', 'requirements', 'rust', 'scss',
  'sql', 'ssh_config', 'toml', 'tsv', 'tsx', 'typescript', 'vim', 'vimdoc',
  'xml', 'yaml',
}

-- No-op for parsers that are already installed.
ts.install(parsers)

local available
local function is_available(lang)
  if not available then
    available = {}
    for _, l in ipairs(require('nvim-treesitter.config').get_available()) do
      available[l] = true
    end
  end
  return available[lang]
end

local function attach(buf, lang)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not pcall(vim.treesitter.start, buf, lang) then
    return
  end
  if vim.treesitter.query.get(lang, 'indents') then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('treesitter_start', { clear = true }),
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(args.match)
    if not lang then
      return
    end
    if vim.treesitter.language.add(lang) then
      attach(args.buf, lang)
    elseif is_available(lang) then
      -- Replaces master's auto_install.
      ts.install(lang):await(function()
        vim.schedule(function()
          attach(args.buf, lang)
        end)
      end)
    end
  end,
})

-- Incremental selection, on top of Neovim 0.12's built-in `an`/`in`.

-- Charwise-select a 0-based, end-exclusive node range.
local function select_range(buf, range)
  local r1, c1, r2, c2 = unpack(range)
  if c2 == 0 then
    r2 = r2 - 1
    c2 = #vim.api.nvim_buf_get_lines(buf, r2, r2 + 1, true)[1]
  end
  if vim.fn.mode():match('^[vV\22]') then
    vim.cmd('normal! \27')
  end
  vim.api.nvim_buf_set_mark(buf, '<', r1 + 1, c1, {})
  vim.api.nvim_buf_set_mark(buf, '>', r2 + 1, math.max(c2 - 1, 0), {})
  vim.cmd('normal! gv')
  if vim.fn.mode() ~= 'v' then
    vim.cmd('normal! v')
  end
end

-- Like master's init_selection: select the smallest node at the cursor.
-- `van` would skip single-character nodes.
local function select_node()
  local buf = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then
    return
  end
  parser:parse(true)
  local node = vim.treesitter.get_node({ ignore_injections = false })
  if node then
    select_range(buf, { node:range() })
  end
end

vim.keymap.set('n', 'gnn', select_node, { desc = 'Select treesitter node' })
vim.keymap.set('x', '+', 'an', { remap = true, desc = 'Expand selection to parent node' })
vim.keymap.set('x', '-', 'in', { remap = true, desc = 'Shrink selection to child node' })

-- Expand the selection to the nearest enclosing @local.scope from the
-- language's locals query, like master's scope_incremental. Falls back to
-- the parent node when the language has no locals query.
local function select_scope()
  local buf = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then
    return
  end
  parser:parse(true)

  local v, c = vim.fn.getpos('v'), vim.fn.getpos('.')
  if v[2] > c[2] or (v[2] == c[2] and v[3] > c[3]) then
    v, c = c, v
  end
  -- 0-based, end-exclusive selection range
  local srow, scol, erow, ecol = v[2] - 1, v[3] - 1, c[2] - 1, c[3]

  local sel = { srow, scol, erow, ecol }
  local function contains(outer, inner)
    local starts_before = outer[1] < inner[1] or (outer[1] == inner[1] and outer[2] <= inner[2])
    local ends_after = outer[3] > inner[3] or (outer[3] == inner[3] and outer[4] >= inner[4])
    return starts_before and ends_after
  end
  local function encloses(r)
    return contains(r, sel) and not vim.deep_equal(r, sel)
  end

  local best
  parser:for_each_tree(function(tree, ltree)
    local query = vim.treesitter.query.get(ltree:lang(), 'locals')
    if not query then
      return
    end
    for id, node in query:iter_captures(tree:root(), buf, srow, erow + 1) do
      if query.captures[id] == 'local.scope' then
        local r = { node:range() }
        if encloses(r) and (not best or contains(best, r)) then
          best = r
        end
      end
    end
  end)

  if not best then
    vim.api.nvim_feedkeys(vim.keycode('an'), 'm', false)
    return
  end
  select_range(buf, best)
end

vim.keymap.set('x', 'grc', select_scope, { desc = 'Expand selection to enclosing scope' })
