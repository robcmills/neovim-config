local M = {}

local function set_unique_buffer_name(bufnr, base_name)
  local count = 1
  local new_name = base_name
  while true do
    local success, err = pcall(vim.api.nvim_buf_set_name, bufnr, new_name)
    if success then
      break
    end
    if err and err:match("Failed to rename buffer") then
      count = count + 1
      new_name = base_name .. count
    else
      break
    end
  end
end

local function parse_ts_ast(file_path)
  -- Step 1: Read file contents
  local file = io.open(file_path, "r")
  if not file then
    vim.notify("Failed to open file: " .. file_path, vim.log.levels.ERROR)
    return
  end
  local content = file:read("*all")
  file:close()

  -- Step 2: Create a temporary buffer (optional but recommended for Tree-sitter API)
  local bufnr = vim.api.nvim_create_buf(false, true) -- Scratch buffer, hidden
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

  -- Step 3: Get the parser for TypeScript
  local parser = vim.treesitter.get_parser(bufnr, "tsx")
  local tree = parser:parse()[1] -- Get the root node of the syntax tree
  local root = tree:root()

  -- Cleanup: Delete the temporary buffer
  vim.api.nvim_buf_delete(bufnr, { force = true })

  return root
end

local function tree()
  print('RefTree:tree:' .. os.date("%Y-%m-%dT%H:%M:%S"))

  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_path = vim.api.nvim_buf_get_name(current_bufnr)

  local function on_list(list)
    local lines = {}
    local seen = {}
    local prefix = "^/Users/robcmills/src/openspace/web/icedemon/"

    for _, item in ipairs(list.items) do
      local path = string.gsub(item.filename, prefix, "")
      if item.filename ~= current_path and not seen[path] then
        seen[path] = true
        local root = parse_ts_ast(item.filename)
        local meta = ""
        if root then
          local zero_based_lnum = item.lnum - 1
          local zero_based_col = item.col - 1
          local node = root:named_descendant_for_range(
            zero_based_lnum,
            zero_based_col,
            zero_based_lnum,
            zero_based_col
          )
          if node then
            meta = node:type()
            if meta == "identifier" then
              meta = vim.treesitter.get_node_text(node, 0)
            end
          end
        end
        table.insert(lines, path .. ":" .. meta)
        -- print(vim.inspect(item))
      end
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    set_unique_buffer_name(bufnr, 'RefTree')
    vim.api.nvim_set_current_buf(bufnr)
  end

  vim.lsp.buf.references(nil, { on_list = on_list })
end

vim.api.nvim_create_user_command('RefTree', function()
  tree()
end, {})

print('RefTree:module:' .. os.date("%Y-%m-%dT%H:%M:%S"))

M.tree = tree

return M
