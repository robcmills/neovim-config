local map = vim.keymap.set

local on_attach = function(_, bufnr)
  map("n", "<leader>k", function()
    vim.lsp.buf.hover()
  end, { desc = "Hover symbol details", buffer = bufnr })
  map("n", "<leader>la", function()
    vim.lsp.buf.code_action()
  end, { desc = "LSP code action", buffer = bufnr })
  map("n", "<leader>lf", function()
    vim.lsp.buf.formatting_sync()
  end, { desc = "Format code", buffer = bufnr })
  map("n", "<leader>lh", function()
    vim.lsp.buf.signature_help()
  end, { desc = "Signature help", buffer = bufnr })
  map("n", "<leader>lr", function()
    vim.lsp.buf.rename()
  end, { desc = "Rename current symbol", buffer = bufnr })
  map("n", "gD", function()
    vim.lsp.buf.declaration()
  end, { desc = "Declaration of current symbol", buffer = bufnr })
  map("n", "gI", function()
    vim.lsp.buf.implementation()
  end, { desc = "Implementation of current symbol", buffer = bufnr })
  map("n", "gd", function()
    vim.lsp.buf.definition()
  end, { desc = "Show the definition of current symbol", buffer = bufnr })

  map("n", "gr", function()
    vim.lsp.buf.references()
  end, { desc = "References of current symbol", buffer = bufnr })

  map("n", "[d", function()
    vim.diagnostic.goto_prev()
  end, { desc = "Previous diagnostic", buffer = bufnr })
  map("n", "]d", function()
    vim.diagnostic.goto_next()
  end, { desc = "Next diagnostic", buffer = bufnr })
  map("n", "gl", function()
    vim.diagnostic.open_float()
  end, { desc = "Hover diagnostics", buffer = bufnr })

  vim.api.nvim_buf_create_user_command(bufnr, "Format", function()
    vim.lsp.buf.formatting_sync()
  end, { desc = "Format file with LSP" })
end

local lsp_defaults = {
  capabilities = require 'cmp_nvim_lsp'.update_capabilities(vim.lsp.protocol.make_client_capabilities()),
  on_attach = on_attach,
}

local lspconfig = require 'lspconfig'

lspconfig.util.default_config = vim.tbl_deep_extend(
  'force',
  lspconfig.util.default_config,
  lsp_defaults
)

-- setup servers
lspconfig.eslint.setup {}

lspconfig.jsonls.setup {}

lspconfig.sqls.setup {}

lspconfig.sumneko_lua.setup {
  on_attach = function(client, bufnr)
    --    client.resolved_capabilities.document_formatting = false
    on_attach(client, bufnr)
    map("n", "<leader>lf", function()
      vim.lsp.buf.formatting_sync {
        tabSize = 2,
        insertSpaces = true,
      }
    end, { desc = "Format lua code", buffer = bufnr })
  end,
  settings = {
    Lua = {
      diagnostics = {
        globals = { "use", "vim" },
      },
    },
  },
}

lspconfig.tsserver.setup {
  cmd = {
    'typescript-language-server',
    '--stdio',
    -- '--log-level', '4',
    -- '--tsserver-log-file', '/Users/robcmills/.cache/nvim/typescript-language-server.log',
    -- '--tsserver-log-verbosity', 'verbose',
  },
  init_options = {
    preferences = {
      importModuleSpecifierPreference = 'non-relative',
      quotePreference = 'single',
    },
  },
  -- settings = {
  --   syntaxes = {
  --     "Packages/TypeScript Syntax/TypeScript.tmLanguage",
  --     "Packages/TypeScript Syntax/TypeScriptReact.tmLanguage",
  --   },
  -- },
}


-- diagnostics
local signs = {
  { name = "DiagnosticSignError", text = "" },
  { name = "DiagnosticSignWarn", text = "" },
  { name = "DiagnosticSignHint", text = "" },
  { name = "DiagnosticSignInfo", text = "" },
}
for _, sign in ipairs(signs) do
  vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = "" })
end

vim.diagnostic.config {
  float = {
    focusable = false,
    style = "minimal",
    border = "rounded",
    source = "always",
    header = "",
    prefix = "",
  },
  severity_sort = true,
  signs = { active = signs },
  underline = true,
  virtual_text = false,
}

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })
