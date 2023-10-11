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

-- builtin.live_grep({opts})                      *telescope.builtin.live_grep()*
--     Search for a string and get results live as you type, respects .gitignore

-- Example:
  -- :lua require('telescope.builtin').live_grep({
  --   prompt_title = 'find string in open buffers...',
  --   grep_open_files = true
  -- })

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
