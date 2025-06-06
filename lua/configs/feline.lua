local colors = require 'colors'

local spacer = function(n)
  return string.rep(' ', n or 1)
end

local lsp_client_names = function()
  local buf_client_names = {}
  for _, client in pairs(vim.lsp.get_clients()) do
    table.insert(buf_client_names, client.name)
  end
  return table.concat(buf_client_names, ", ")
end

require('feline').setup({
  disable = { filetypes = { '^NvimTree$', '^neo%-tree$', '^dashboard$', '^Outline$', '^aerial$' } },
  components = {
    active = {
      {
        { provider = spacer() },
        { provider = 'git_branch', hl = { fg = colors.purple }, opts = { truncate_hide = true } },
        { provider = spacer(2) },
        { provider = { name = 'file_info', opts = { type = 'relative' } }, hl = { fg = colors.fg_dark }, priority = 1 },
      },
      {
        { provider = lsp_client_names, icon = "   ", hl = { fg = colors.blue }, truncate_hide = true },
        { provider = spacer(2) },
        { provider = 'position' },
        { provider = spacer(2) },
        { provider = 'line_percentage', hl = { fg = colors.green } },
      },
    },
  },
})
