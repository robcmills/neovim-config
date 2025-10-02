local M = {}

local MAX_DEPTH = 5

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

---@param bufnr number Buffer number
---@param text string Text to append to buffer
---Appends text to the end of the buffer. Does not create new lines unless text contains newlines.
local function append_to_buffer(bufnr, text)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    print('append_to_buffer: buffer not valid')
    return
  end

  if not vim.bo[bufnr].modifiable then
    print('append_to_buffer: buffer not modifiable')
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local text_parts = vim.split(text, "\n")

  if line_count == 0 then
    -- Empty buffer, just set the text parts
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text_parts)
    return
  end

  -- Get only the last line
  local last_line_idx = line_count - 1
  local last_line = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, last_line_idx + 1, false)[1] or ""

  -- Handle the first part (append to current line)
  if #text_parts > 0 then
    vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx + 1, false, { last_line .. text_parts[1] })
  end

  -- Handle remaining parts (each becomes a new line)
  if #text_parts > 1 then
    local new_lines = {}
    for i = 2, #text_parts do
      table.insert(new_lines, text_parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, new_lines)
  end
end

local function debug_node(node, bufnr)
  local start_row, start_col, _, end_col = node:range()
  local child_count = node:child_count()
  local parent = node:parent()
  local parent_type = parent and parent:type() or "no parent"

  print("Node details:")
  print(" Type:", node:type())
  print(" Child count:", child_count)
  print(" Parent type:", parent_type)

  if child_count > 0 then
    print(" Child types:")
    for i = 0, child_count - 1 do
      local child = node:child(i)
      print("    ", i, ":", child:type())
    end
  end

  -- Print the line with column markers
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)
  local line = lines[1] or ""  -- Handle empty buffer
  print(line)
  print(string.rep(" ", start_col) .. "^" .. string.rep(" ", end_col - start_col - 1) .. "^")
end

local function wait(ms, callback)
  vim.defer_fn(callback, ms)
end

-- Given a position in a file:
-- parse the file into an AST
-- traverse up the AST to find the top-level node
-- return its position
local function get_top_level_position(file_path, row, col)
  local content = vim.fn.readfile(file_path)
  if vim.tbl_isempty(content) then
    return nil
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

  -- Todo: get lang from file extension (support multiple languages)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
  if not ok then
    print("Failed to get parser for file:", file_path)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  local s_row, s_col = row - 1, col - 1
  local node = root:named_descendant_for_range(s_row, s_col, s_row, s_col)
  if not node then
    print("No descendant node found at position, falling back to line range")
    -- Fallback to line range
    node = root:named_descendant_for_range(s_row, 0, s_row, 10000)
  end

  if not node then
    print("No descendant node found")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end

  -- skip imports
  if node:parent() and node:parent():type() == "import_specifier" then
    return nil
  end

  -- Traverse up to the top-level node (direct child of root)
  local top_node = node:parent()
  while top_node and top_node ~= root do
    local parent = top_node:parent()
    if not parent or parent:type() == "program" then break end
    top_node = parent
  end

  if not top_node or top_node == root then
    print("Failed to find top node")
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end

  -- debug_node(top_node, bufnr)

  vim.api.nvim_buf_delete(bufnr, { force = true })

  local start_row, start_col = top_node:range()
  return { line = start_row, col = start_col }
end

local function format_path(path)
  local prefix = "/Users/robcmills/src/openspace/web/icedemon/src/js/"
  if string.sub(path, 1, #prefix) == prefix then
    return string.sub(path, #prefix + 1)
  else
    return path
  end
end

local function print_buffer_info(bufnr)
  -- Get buffer name
  local name = vim.api.nvim_buf_get_name(bufnr)

  -- Get filetype
  local filetype = vim.bo[bufnr].filetype

  -- Get first line (line 0 to 1, no strict index)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
  local first_line = lines[1] or ""

  -- Print the info
  print("Buffer Number: " .. bufnr)
  print("Buffer Name: " .. name)
  print("Filetype: " .. filetype)
  print("First Line: " .. first_line)
end

local function create_temp_buffer(path)
  local bufnr = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
  local content = vim.fn.readfile(path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.api.nvim_buf_set_name(bufnr, path)
  local filetype = vim.filetype.match({filename = path}) or ""
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

local function create_didopen_params(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    -- Handle unnamed buffers (optional: skip or use a dummy URI)
    vim.notify('Buffer ' .. bufnr .. ' has no name; skipping didOpen', vim.log.levels.WARN)
    return nil
  end

  local uri = vim.uri_from_bufnr(bufnr)

  -- Get language ID from filetype (trim whitespace if needed)
  local language_id = vim.bo[bufnr].filetype:gsub("^%s*(.-)%s*$", "%1")
  if language_id == '' then
    language_id = 'plaintext'  -- Fallback for unknown filetypes
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)  -- false: include \n on last line if present
  local text = table.concat(lines, '\n')

  local params = {
    textDocument = {
      uri = uri,
      languageId = language_id,
      version = 0,  -- Initial version; increment manually for future didChange if needed
      text = text,
    }
  }

  return params
end

local function register_buffer(temp_bufnr, client_bufnr)
  local clients = vim.lsp.get_clients({ bufnr = client_bufnr })
  if vim.tbl_isempty(clients) then
    vim.notify("Failed to register_buffer: no clients attached to client_bufnr", vim.log.levels.WARN)
    return false
  end

  -- Attach clients to the temp buffer (mimics LspAttach autocmd)
  for _, client in ipairs(clients) do
    if client.name == "ts_ls" and client.supports_method("textDocument/references") then
      local success = vim.lsp.buf_attach_client(temp_bufnr, client.id)
      if not success then
        vim.notify("Failed to attach " .. client.name .. " client to temp buffer", vim.log.levels.WARN)
      end
    end
  end

  -- Send textDocument/didOpen notification (triggers server to parse/load)
  local open_params = create_didopen_params(temp_bufnr)
  if open_params then
    local success = vim.lsp.buf_notify(temp_bufnr, "textDocument/didOpen", open_params)
    if not success then
      vim.notify("Failed to notify lsp", vim.log.levels.WARN)
    end
  else
    vim.notify("Failed to create didOpen params for temp buffer", vim.log.levels.WARN)
    return false
  end

  return true
end

local function unregister_buffer(bufnr, client_bufnr)
  local close_params = vim.lsp.util.make_text_document_params(bufnr)
  vim.lsp.buf_notify(bufnr, "textDocument/didClose", close_params)

  local clients = vim.lsp.get_clients({ bufnr = client_bufnr })
  for _, client in ipairs(clients) do
    if client.name == "ts_ls" then
      pcall(vim.lsp.buf_detach_client, bufnr, client.id)
    end
  end
end

-- Function to add references recursively to a node (async via callback)
local function visit_node(node, client_bufnr, ref_tree_bufnr, on_done)
  local indent = string.rep("  ", node.depth)
  append_to_buffer(ref_tree_bufnr, "\n" .. indent .. format_path(node.path))

  -- Load file content into temp buffer and register with LSP client
  local temp_bufnr = -1
  local existing_bufnr = vim.fn.bufnr(node.path)
  if existing_bufnr < 0 then
    temp_bufnr = create_temp_buffer(node.path)
    -- print_buffer_info(temp_bufnr)
    register_buffer(temp_bufnr, client_bufnr)
  end

  local function cleanup_temp_buf()
    if temp_bufnr > 0 then
      unregister_buffer(temp_bufnr, client_bufnr)
      vim.api.nvim_buf_delete(temp_bufnr, { force = true })
    end
  end

  local function get_references()
    local file_uri = vim.uri_from_fname(node.path)
    local position = node.position
    local params = {
      textDocument = { uri = file_uri },
      position = { line = position.line, character = position.col },
      context = { includeDeclaration = false },
    }
    -- append_to_buffer(ref_tree_bufnr, "\n" .. indent .. "buf_request params: " .. vim.inspect(params))

    vim.lsp.buf_request(client_bufnr, "textDocument/references", params, function(err, result)
      if err then
        append_to_buffer(ref_tree_bufnr, "\nbuf_request err: " .. vim.inspect(err))
        cleanup_temp_buf()
        on_done()
        return
      end
      if not result then
        append_to_buffer(ref_tree_bufnr, "\nbuf_request result nil")
        cleanup_temp_buf()
        on_done()
        return
      end

      append_to_buffer(ref_tree_bufnr, "\n" .. indent .. "buf_request result: " .. #result)
      cleanup_temp_buf()

      -- Step 1: Synchronously build node.children from results (no recursion yet)
      for _, loc in ipairs(result) do
        local ref_path = vim.uri_to_fname(loc.uri)
        if ref_path ~= node.path then
          local ref_row = loc.range.start.line + 1
          local ref_col = loc.range.start.character + 1
          local top_pos = get_top_level_position(ref_path, ref_row, ref_col)
          if top_pos then
            local child = {
              children = {},
              depth = node.depth + 1,
              path = ref_path,
              position = top_pos
            }
            table.insert(node.children, child)
          end
        end
      end

      -- Step 2: If recursion allowed, process children sequentially (depth-first, no interleaving)
      if node.depth < MAX_DEPTH then
        local function process_next(idx)
          if idx > #node.children then
            on_done()  -- All siblings done
            return
          end
          local child = node.children[idx]
          visit_node(child, client_bufnr, ref_tree_bufnr, function()
            process_next(idx + 1)  -- Proceed to next sibling only after this subtree is fully done
          end)
        end
        process_next(1)
      else
        on_done()  -- No recursion; done with this node
      end
    end)
  end

  -- Delay after registering new buffer to allow LSP server to parse it
  if temp_bufnr > 0 then
    wait(2000, get_references)  -- delay for new buffers
  else
    get_references()  -- No delay for already-loaded buffers
  end
end

-- Depth-first print tree with indentation
local function print_tree(node, indent)
  indent = indent or ""
  print(indent .. node.path)

  -- Sort children by path for consistent output
  table.sort(node.children, function(a, b)
    return a.path < b.path
  end)

  local child_indent = indent .. "  "
  for _, child in ipairs(node.children) do
    print_tree(child, child_indent)
  end
end

local function create_ref_tree_buffer()
  local bufnr = vim.api.nvim_create_buf(true, false)
  -- vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  set_unique_buffer_name(bufnr, 'RefTree')
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

-- Main function to build and print the reference tree
function M.ref_tree()
  -- build root node on current buffer cursor position
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_path = vim.api.nvim_buf_get_name(current_bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)

  -- Create a new buffer for the ref tree. We'll stream the tree into it as we build.
  local ref_tree_bufnr = create_ref_tree_buffer()

  if not current_path or current_path == "" then
    append_to_buffer(ref_tree_bufnr, "No file in current buffer")
    return
  end

  local line = cursor[1] - 1
  local col = cursor[2] - 1
  local root = {
    depth = 0,
    path = current_path,
    position = { line = line, col = col },
    children = {},
  }
  -- append_to_buffer(ref_tree_bufnr, vim.inspect(root))

  visit_node(root, current_bufnr, ref_tree_bufnr, function()
    -- tree fully built and appended
  end)
end

vim.api.nvim_create_user_command('RefTree', function()
  M.ref_tree()
end, {})

return M
