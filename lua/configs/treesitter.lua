require'nvim-treesitter.configs'.setup {
  auto_install = true,
  autotag = { enable = true },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
  indent = { enable = true },
}
