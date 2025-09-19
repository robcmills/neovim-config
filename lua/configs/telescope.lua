local sorters = require('telescope.sorters')

local git_sorter = sorters.Sorter:new({
  scoring_function = function(_, prompt, line, entry)
    print('line', vim.inspect(line))
    print('entry', vim.inspect(entry))
    return -string.len(line)
  end
})

local path_display = function(_, path)
  local tail = require("telescope.utils").path_tail(path)
  path = string.gsub(path, "src/js/", "")
  path = string.gsub(path, tail .. "$", "")
  return string.format("%s  |  %s", tail, path)
end

local telescope = require('telescope')

telescope.setup({
  defaults = {
    prompt_prefix = '   ',
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
    buffers = {
      layout_config = {
      vertical = {
          prompt_position = 'top',
      },
      width = 0.75,
      height = 0.75,
      },
      layout_strategy = 'vertical',
      path_display = path_display,
      show_line = false,
      sort_lastused = true,
    },
    find_files = {
      hidden = false,
    },
    -- live_grep = {
      -- sorter = git_sorter,
    -- },
    lsp_definitions = {
      path_display = path_display,
      show_line = false,
    },
    lsp_references = {
      show_line = false
    },
  },
  extensions = {
    fzf = {
      case_mode = "ignore_case", -- or "smart_case" (default) or "respect_case"
    },
  },
})

telescope.load_extension('fzf')

-- Default Mappings
-- <C-q> Send all items not filtered to quickfixlist (qflist)

-- Examples
-- :lua require('telescope.builtin').live_grep({ cwd = '.github' })
-- :lua require('telescope.builtin').live_grep({ cwd = 'e2e' })
-- :lua require('telescope.builtin').live_grep({ cwd = 'src/js/projects/site/SheetsAlignmentTab' })
-- :lua require('telescope.builtin').live_grep({ cwd = '~/local/share/nvim/prompt/history' })
-- :lua require('telescope.builtin').live_grep({ glob_pattern = "!yarn.lock" })
-- :lua require('telescope.builtin').live_grep({ glob_pattern = "!node_modules", hidden = false })
-- :lua require('telescope.builtin').live_grep({ no_ignore = true })
-- :lua require('telescope.builtin').find_files({ cwd = 'src/js/openapi', no_ignore = true })
-- :lua require('telescope.builtin').find_files({ cwd = 'prompt_history' })
-- :lua require('telescope.builtin').find_files({ cwd = '~/.local/share/nvim/prompt/history', sorting_strategy = "descending" })
-- :lua require('telescope.builtin').find_files({ cwd = '~/.local/share/nvim/prompt/history', find_command = { "bash", "-c", "ls -1 *.md | sort -r" } })

-- ls -1 *.md | sort -r


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

--                                     *telescope.defaults.generic_sorter*
-- generic_sorter:
--     A function pointer to the generic sorter. The sorter that should be
--     used for everything that is not a file.
--     Hint: If you load a native sorter, you don't need to change this value,
--     the native sorter will override it anyway.
--
--     Default: require("telescope.sorters").get_fzy_sorter
--
--                                   *telescope.defaults.prefilter_sorter*
