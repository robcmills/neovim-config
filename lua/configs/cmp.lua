local cmp = require 'cmp'

vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }

cmp.setup({
  mapping = cmp.mapping.preset.insert {
    ['<cr>'] = cmp.mapping.confirm { select = true },
  },
  snippet = {
    -- REQUIRED - you must specify a snippet engine
    expand = function(args)
      require 'luasnip'.lsp_expand(args.body) -- For `luasnip` users.
      -- require('snippy').expand_snippet(args.body) -- For `snippy` users.
      -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
    end,
  },
  sources = {
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
    { name = 'path' },
    { name = 'buffer' },
  },
})

-- Set configuration for specific filetype.
cmp.setup.filetype('gitcommit', {
  sources = cmp.config.sources({
    { name = 'cmp_git' }, -- You can specify the `cmp_git` source if you were installed it.
  }, {
    { name = 'buffer' },
  })
})

-- Use buffer source for `/`
-- (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline('/', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = {
    { name = 'buffer' }
  }
})

-- Use cmdline & path source for ':'
-- (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  })
})

cmp.setup.filetype({ 'sql' }, {
  sources = {
    { name = 'vim-dadbod-completion' },
    { name = 'buffer' },
  },
})

-- Setup lspconfig.
--
-- require 'lspconfig'.eslint.setup {
--   capabilities = capabilities
-- }
-- require 'lspconfig'.tsserver.setup {
--   capabilities = capabilities
-- }
-- require 'lspconfig'.sumneko_lua.setup {
--   capabilities = capabilities
-- }
-- require 'lspconfig'.jsonls.setup {
--   capabilities = capabilities
-- }
