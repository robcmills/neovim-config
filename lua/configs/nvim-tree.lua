require 'nvim-tree'.setup {
  hijack_unnamed_buffer_when_opening = true,
  open_on_setup = true,
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
