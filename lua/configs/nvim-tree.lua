require 'nvim-tree'.setup {
  hijack_unnamed_buffer_when_opening = true,
  update_focused_file = { enable = true },
  remove_keymaps = { "e", "E" }, -- clashes with colemak bindings
  renderer = {
    icons = {
      git_placement = 'signcolumn',
      glyphs = {
        git = {
          unstaged = "u",
          staged = "s",
          unmerged = "",
          renamed = "r",
          untracked = "+",
          deleted = "-",
          ignored = "i",
        },
      },
    },
  },
  view = {
    adaptive_size = true,
    centralize_selection = true,
    side = 'left',
  },
}

local function open_nvim_tree()
  require("nvim-tree.api").tree.open()
end

vim.api.nvim_create_autocmd({ "VimEnter" }, { callback = open_nvim_tree })
