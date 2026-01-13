local map = vim.keymap.set

local remove_unused_imports = function(bufnr)
  local method = vim.lsp.protocol.Methods.textDocument_codeAction
  local range_params = vim.lsp.util.make_range_params(0, 'utf-8')
  local params = {
    textDocument = range_params.textDocument,
    range = range_params.range,
    context = {
      only = { "source.removeUnusedImports" },
      triggerKind = 1,
    },
  }
  local timeout_ms = 1000
  local result = vim.lsp.buf_request_sync(bufnr, method, params, timeout_ms)
  if not result or vim.tbl_isempty(result) then
    return
  end
  for _, res in pairs(result) do
      for _, r in pairs(res.result or {}) do
          if r.edit then
              vim.lsp.util.apply_workspace_edit(r.edit, 'utf-8')
          end
      end
  end
end

local add_missing_imports = function(bufnr)
  local method = vim.lsp.protocol.Methods.textDocument_codeAction
  local range_params = vim.lsp.util.make_range_params(0, 'utf-8')
  local params = {
    textDocument = range_params.textDocument,
    range = range_params.range,
    context = {
      only = { "source.addMissingImports" },
      triggerKind = 1
    }
  }
  local timeout_ms = 1000
  local result = vim.lsp.buf_request_sync(bufnr, method, params, timeout_ms)
  if not result or vim.tbl_isempty(result) then
    return
  end
  for _, res in pairs(result) do
      for _, r in pairs(res.result or {}) do
          if r.edit then
              vim.lsp.util.apply_workspace_edit(r.edit, 'utf-8')
          end
      end
  end
  -- Shorter version but is async
  -- vim.lsp.buf.code_action({
  --   context = { only = { "source.addMissingImports" } },
  --   apply = true,
  -- })
end

local on_attach = function(_, bufnr)
  map("n", "<leader>k", function()
    vim.lsp.buf.hover({ border = "rounded" })
  end, { desc = "Hover symbol details" })
  map("n", "<leader>la", function()
    vim.lsp.buf.code_action()
  end, { desc = "LSP code action" })

  map("n", "<leader>a", function()
    vim.lsp.buf.code_action({
      apply = true,
      context = {
        diagnostics = vim.lsp.diagnostic.get_line_diagnostics(),
        only = { "source.fixAll" }
      },
    })
  end, { desc = "Fix all" })

  map("n", "<leader>li", function()
    add_missing_imports(bufnr)
  end, { desc = "Fix imports" })

  map("n", "<leader>lv", function()
    remove_unused_imports(bufnr)
  end, { desc = "Remove unused imports" })

  map("n", "<leader>lf", function()
    vim.lsp.buf.format()
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
    vim.diagnostic.jump({count=-1, float=true})
  end, { desc = "Previous diagnostic", buffer = bufnr })
  map("n", "]d", function()
    vim.diagnostic.jump({count=1, float=true})
  end, { desc = "Next diagnostic", buffer = bufnr })
  map("n", "gl", function()
    vim.diagnostic.open_float()
  end, { desc = "Hover diagnostics", buffer = bufnr })

  vim.api.nvim_buf_create_user_command(bufnr, "Format", function()
    vim.lsp.buf.formatting_sync()
  end, { desc = "Format file with LSP" })
end

-- setup servers

-- vim.lsp.config.eslint = {}
vim.lsp.enable('eslint')

-- vim.lsp.config.jsonls = {}
vim.lsp.enable('jsonls')

-- vim.lsp.config.sqlls = {}
vim.lsp.enable('sqlls')


-- pico-8
vim.filetype.add({
  extension = {
    p8 = 'pico8',
  },
})
vim.lsp.config.pico8_ls = {
  cmd = { 'pico8-ls', '--stdio' },
  filetypes = { 'pico8', 'p8' },
  on_attach = on_attach,
}
vim.lsp.enable('pico8_ls')


-- lua
vim.lsp.config.lua_ls = {
  on_attach = function(client, bufnr)
    --    client.resolved_capabilities.document_formatting = false
    on_attach(client, bufnr)
    vim.keymap.set("n", "<leader>lf", function()
      vim.lsp.buf.format {
        format_opts = {
          tabSize = 2,
          insertSpaces = true,
        },
      }
    end, { desc = "Format lua code", buffer = bufnr })
  end,
  settings = {
    Lua = {
      diagnostics = {
        globals = { "use", "vim", 'hs' },
      },
      format = {
        enable = true,
        defaultConfig = {
          indent_style = "space",
          indent_size = "2",
        },
      },
      runtime = {
        version = 'LuaJIT',
      },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
        -- library = vim.api.nvim_get_runtime_file("", true),
      }
    },
  },
}
vim.lsp.enable('lua_ls')

vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  callback = function()
    vim.bo.shiftwidth = 2 -- Set 'shiftwidth' to 2
    vim.bo.tabstop = 2    -- Set 'tabstop' to 2
    vim.bo.expandtab = true -- Use spaces instead of tabs

    -- Optionally set up custom format command using LSP
    -- vim.keymap.set("n", "<leader>f", function()
    --   vim.lsp.buf.format({
    --     filter = function(client)
    --       return client.name == "lua_ls" -- your LSP client name for Lua
    --     end,
    --     formatting_options = {
    --       insertSpaces = true,
    --       tabSize = 2,
    --     },
    --   })
    -- end, { buffer = true })
  end,
})

vim.lsp.config.ts_ls = {
  init_options = {
    preferences = {
      importModuleSpecifierPreference = 'non-relative',
      quotePreference = 'single',
    },
  },
  on_attach = on_attach,
}
vim.lsp.enable('ts_ls')


-- deno config
-- vim.g.markdown_fenced_languages = {
--   "ts=typescript"
-- }
-- vim.lsp.config.denols = {
--   on_attach = on_attach,
--   root_dir = util.root_pattern("deno.json", "deno.jsonc")
-- }
-- vim.lsp.enable('denols')


--Enable (broadcasting) snippet capability for completion
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true

vim.lsp.config.cssls = {
  capabilities = capabilities
}
vim.lsp.enable('cssls')


-- diagnostics
vim.diagnostic.config({
  float = {
    focusable = true,
    style = "minimal",
    border = "rounded",
    source = true,
    header = "",
    prefix = "",
  },
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN]  = "",
      [vim.diagnostic.severity.HINT]  = "",
      [vim.diagnostic.severity.INFO]  = "",
    },
    -- optional: set number highlighting
    numhl = {
      [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
      [vim.diagnostic.severity.WARN]  = "DiagnosticSignWarn",
      [vim.diagnostic.severity.HINT]  = "DiagnosticSignHint",
      [vim.diagnostic.severity.INFO]  = "DiagnosticSignInfo",
    },
  },
  underline = true,
  virtual_text = true,
})

-- todo: migrate these
-- vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
-- vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })
