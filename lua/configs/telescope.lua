require('telescope').setup({
  defaults = {
    prompt_prefix = '   ',
    selection_caret = '❯ ',
    path_display = { 'truncate' },
    sorting_strategy = 'ascending',
    layout_strategy = 'horizontal',
    layout_config = {
      horizontal = {
        prompt_position = 'top',
        preview_width = 0.5,
        results_width = 0.5,
      },
      width = 0.99,
      height = 0.99,
      preview_cutoff = 120,
    },
    mappings = {
      i = {
        ["<C-n>"] = require('telescope.actions').cycle_history_next,
        ["<C-e>"] = require('telescope.actions').cycle_history_prev,
      },
    },
    vimgrep_arguments = {
      "rg",
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--ignore-case",
      -- "--no-ignore",
    },
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

-- Default Mappings
-- <C-q> Send all items not filtered to quickfixlist (qflist)

-- Examples
-- :lua require('telescope.builtin').live_grep({ cwd = .github })
-- :lua require('telescope.builtin').live_grep({ glob_pattern = "!yarn.lock" })
-- :lua require('telescope.builtin').live_grep({ glob_pattern = "!node_modules", hidden = false })
-- :lua require('telescope.builtin').find_files({ cwd = 'src/js/openapi', no_ignore = true })

-- builtin.live_grep({opts})                      *telescope.builtin.live_grep()*
--     Search for a string and get results live as you type, respects .gitignore
-- Options:  
  -- {cwd}                 (string)          root dir to search from (default: cwd, use utils.buffer_dir() to search relative to open buffer)
  -- {grep_open_files}     (boolean)         if true, restrict search to open files only, mutually exclusive with `search_dirs`
  -- {search_dirs}         (table)           directory/directories/files to search, mutually exclusive with `grep_open_files`
  -- {glob_pattern}        (string|table)    argument to be used with `--glob`, e.g. "*.toml", can use the opposite "!*.toml"
  -- {type_filter}         (string)          argument to be used with `--type`, e.g. "rust", see `rg type-list`
  -- {additional_args}     (function|table)  additional arguments to be passed on. Can be fn(opts) -> tbl
  -- {max_results}         (number)          define a upper result value
  -- {disable_coordinates} (boolean)         don't show the line & row numbers (default: false)
  -- {file_encoding}       (string)          file encoding for the entry & previewer
