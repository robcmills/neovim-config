require 'gitsigns'.setup {
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns
    vim.keymap.set('n', '<leader>hb', function() gs.blame_line{full=true} end)
    vim.keymap.set('n', '<leader>gb', gs.toggle_current_line_blame)
  end
}
