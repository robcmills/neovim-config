-- splash screen: the Neovim logo from splash.txt, colored like the real logo,
-- centered with the version underneath

local M = {}

local ns = vim.api.nvim_create_namespace('splash')

-- Each logo region has a top and bottom color; rows blend between them like
-- the gradients in the official logo. `solid` swaps the shade glyphs for full
-- blocks so color alone draws the shape.
M.palettes = {
  logo = {
    solid = true,
    left = { '#40B4E8', '#3574C0' }, -- blue left column
    cap = { '#7BC86C', '#5FA857' }, -- green cap over the top of the left column
    diagonal = { '#A0D06E', '#62A35E' }, -- light green diagonal
    right = { '#80B444', '#427E33' }, -- green right column
    overlap = { '#58A044', '#43893A' }, -- bottom of the right column, under the diagonal
    text = '#7A8478',
  },
  logo_shaded = {
    solid = false,
    left = { '#40B4E8', '#3574C0' },
    cap = { '#7BC86C', '#5FA857' },
    diagonal = { '#A0D06E', '#62A35E' },
    right = { '#80B444', '#427E33' },
    overlap = { '#58A044', '#43893A' },
    text = '#7A8478',
  },
  flat = {
    solid = true,
    left = { '#3D9BDB', '#3D9BDB' },
    cap = { '#6DB862', '#6DB862' },
    diagonal = { '#8CC265', '#8CC265' },
    right = { '#5E9B3D', '#5E9B3D' },
    overlap = { '#4E953F', '#4E953F' },
    text = '#7A8478',
  },
  vivid = {
    solid = true,
    left = { '#4FD1FF', '#2F6FE0' },
    cap = { '#7DE07A', '#4FBF5A' },
    diagonal = { '#B8F07A', '#5DC264' },
    right = { '#8FD13F', '#3C8A2A' },
    overlap = { '#5BBF45', '#3A9A38' },
    text = '#8A9A88',
  },
  tokyonight = {
    solid = true,
    left = { '#7DCFFF', '#7AA2F7' },
    cap = { '#9ECE6A', '#73A85A' },
    diagonal = { '#C3E88D', '#8DB86A' },
    right = { '#9ECE6A', '#5F8A45' },
    overlap = { '#73A85A', '#5F8A45' },
    text = '#565F89',
  },
}

-- Vivid with a darker right column and an overlap that stands out from it
local function vivid_variant(right, overlap)
  return vim.tbl_extend('force', M.palettes.vivid, { right = right, overlap = overlap })
end
M.palettes.vivid_bright = vivid_variant({ '#8FD13F', '#2C6A1E' }, { '#74E05A', '#4CC040' })
M.palettes.vivid_emerald = vivid_variant({ '#8FD13F', '#2C6A1E' }, { '#2FCB6A', '#1A9E4E' })
M.palettes.vivid_mint = vivid_variant({ '#8FD13F', '#2A6219' }, { '#55E6A0', '#2DBF73' })
M.palettes.vivid_deep = vivid_variant({ '#9AD94A', '#3A7F26' }, { '#2E8F2E', '#1B6624' })

local function hex_to_rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function blend(a, b, t)
  local ar, ag, ab = hex_to_rgb(a)
  local br, bg, bb = hex_to_rgb(b)
  local function mix(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return string.format('#%02X%02X%02X', mix(ar, br), mix(ag, bg), mix(ab, bb))
end

local function read_logo()
  local path = vim.fn.stdpath('config') .. '/lua/splash.txt'
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  while #lines > 0 and vim.trim(lines[#lines]) == '' do
    table.remove(lines)
  end
  return lines
end

-- Map a glyph to its logo region. '▓' draws both the cap (top left) and the
-- overlap (bottom right), so the column decides which.
local function region(char, col)
  if char == '█' then return 'left' end
  if char == '▒' then return 'diagonal' end
  if char == '░' then return 'right' end
  if char == '▓' then return col < 12 and 'cap' or 'overlap' end
end

local function current_palette()
  return M.palettes[vim.g.splash_palette] or M.palettes.vivid_emerald
end

local function render(buf, win)
  local palette = current_palette()
  local logo = read_logo()
  local v = vim.version()
  local version = string.format('NVIM v%d.%d.%d', v.major, v.minor, v.patch)

  local logo_width = 0
  for _, line in ipairs(logo) do
    logo_width = math.max(logo_width, vim.fn.strdisplaywidth(line))
  end

  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)
  local top = math.max(0, math.floor((win_height - (#logo + 2)) / 2))
  local left = string.rep(' ', math.max(0, math.floor((win_width - logo_width) / 2)))

  local lines = {}
  for _ = 1, top do
    table.insert(lines, '')
  end

  -- Build each logo row glyph by glyph so every glyph gets its region's color
  -- for that row
  local marks = {}
  for row, line in ipairs(logo) do
    local t = #logo > 1 and (row - 1) / (#logo - 1) or 0
    local out = { left }
    local byte = #left
    for col, char in ipairs(vim.fn.split(line, '\\zs')) do
      local r = region(char, col - 1)
      local glyph = (r and palette.solid) and '█' or char
      if r then
        local group = string.format('Splash_%s_%d', r, row)
        vim.api.nvim_set_hl(0, group, { fg = blend(palette[r][1], palette[r][2], t) })
        table.insert(marks, { #lines, byte, byte + #glyph, group })
      end
      table.insert(out, glyph)
      byte = byte + #glyph
    end
    table.insert(lines, table.concat(out))
  end

  table.insert(lines, '')
  local text_pad = math.max(0, math.floor((win_width - #version) / 2))
  table.insert(lines, string.rep(' ', text_pad) .. version)
  vim.api.nvim_set_hl(0, 'SplashVersion', { fg = palette.text, bold = true })
  table.insert(marks, { #lines - 1, text_pad, text_pad + #version, 'SplashVersion' })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

-- Show the splash in the current window. It is an unlisted scratch buffer
-- that wipes itself once another buffer replaces it.
function M.show()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'splash'
  vim.api.nvim_win_set_buf(win, buf)

  -- setlocal values belong to this buffer in this window, so a file opened
  -- here gets the normal options back
  for opt, value in pairs({
    number = false,
    relativenumber = false,
    cursorline = false,
    colorcolumn = '',
    signcolumn = 'no',
    list = false,
    wrap = false,
  }) do
    vim.api.nvim_set_option_value(opt, value, { scope = 'local', win = win })
  end

  render(buf, win)

  vim.api.nvim_create_autocmd('VimResized', {
    group = vim.api.nvim_create_augroup('splash', { clear = true }),
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then return true end
      local buf_win = vim.fn.bufwinid(buf)
      if buf_win ~= -1 then render(buf, buf_win) end
    end,
  })
end

return M
