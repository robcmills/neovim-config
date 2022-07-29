require 'nvim-tree'.setup {
  hijack_unnamed_buffer_when_opening = true,
  open_on_setup = true,
  update_focused_file = { enable = true },
  renderer = {
    icons = {
      git_placement = 'signcolumn',
    },
  },
  view = {
    adaptive_size = true,
    centralize_selection = true,
    side = 'left',
  },
  actions = {
    open_file = {
      -- quit_on_open = true,
    },
  },
}
