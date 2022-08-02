local actions = require 'telescope.actions'
require 'telescope'.setup({
  defaults = {
    prompt_prefix = '  ',
    selection_caret = '❯ ',
    path_display = { 'truncate' },
    sorting_strategy = 'ascending',
    layout_strategy = 'horizontal',
    layout_config = {
      horizontal = {
        prompt_position = 'top',
        preview_width = 0.4,
        results_width = 0.6,
      },
      width = 0.9,
      height = 0.9,
      preview_cutoff = 120,
    },
    --    file_ignore_patterns = '',
  },
  pickers = {
    find_files = {
      hidden = true,
    },
    lsp_references = {
      show_line = false
    },
  },
  extensions = {},
})
