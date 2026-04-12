local M = {}

-- ---------------------------------------------------------------------------
-- Session Discovery
-- ---------------------------------------------------------------------------

local claude_dir = vim.fn.expand('~/.claude')

-- Convert a cwd path to the project slug Claude Code uses
-- e.g. /Users/robcmills/.config -> -Users-robcmills--config
local function cwd_to_slug(cwd)
  return cwd:gsub('/', '-')
end

-- Read all session metadata files and return a list of session info tables
local function read_session_metadata()
  local sessions_dir = claude_dir .. '/sessions'
  local files = vim.fn.glob(sessions_dir .. '/*.json', false, true)
  local sessions = {}
  for _, filepath in ipairs(files) do
    local ok, content = pcall(vim.fn.readfile, filepath)
    if ok and content[1] then
      local decoded = vim.json.decode(content[1])
      if decoded then
        table.insert(sessions, decoded)
      end
    end
  end
  return sessions
end

-- Check if a PID is alive
local function pid_alive(pid)
  if not pid then return false end
  local ok, err = pcall(vim.uv.kill, pid, 0)
  return ok and not err
end

-- Get child PIDs of a given parent PID (macOS: pgrep -P)
local function get_child_pids(ppid)
  local result = vim.fn.systemlist('pgrep -P ' .. ppid)
  local pids = {}
  for _, line in ipairs(result) do
    local pid = tonumber(line)
    if pid then table.insert(pids, pid) end
  end
  return pids
end

-- Recursively get all descendant PIDs
local function get_descendant_pids(ppid)
  local children = get_child_pids(ppid)
  local all = {}
  for _, child in ipairs(children) do
    table.insert(all, child)
    local descendants = get_descendant_pids(child)
    for _, d in ipairs(descendants) do
      table.insert(all, d)
    end
  end
  return all
end

-- Build a set from a list for O(1) lookups
local function set_from_list(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

-- Find JSONL path for a given session ID, searching all project dirs
local function find_jsonl_path(session_id)
  local projects_dir = claude_dir .. '/projects'
  local dirs = vim.fn.glob(projects_dir .. '/*', false, true)
  for _, dir in ipairs(dirs) do
    local path = dir .. '/' .. session_id .. '.jsonl'
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

-- Primary discovery: check if current buffer is a terminal running Claude Code
local function discover_from_current_buffer(all_sessions)
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= 'terminal' then
    return nil
  end

  local job_pid = vim.b[bufnr].terminal_job_pid
  if not job_pid then return nil end

  -- Get all descendant PIDs of the terminal shell
  local descendants = get_descendant_pids(job_pid)
  local desc_set = set_from_list(descendants)

  -- Also check the job_pid itself
  desc_set[job_pid] = true

  -- Match against session metadata
  for _, session in ipairs(all_sessions) do
    if desc_set[session.pid] then
      return session
    end
  end
  return nil
end

-- Fallback discovery: find sessions matching current cwd
local function discover_from_cwd(all_sessions)
  local cwd = vim.fn.getcwd()
  local matches = {}

  for _, session in ipairs(all_sessions) do
    if session.cwd == cwd then
      table.insert(matches, session)
    end
  end

  if #matches == 0 then return nil end

  -- Separate alive vs dead
  local alive = {}
  local dead = {}
  for _, session in ipairs(matches) do
    if pid_alive(session.pid) then
      table.insert(alive, session)
    else
      table.insert(dead, session)
    end
  end

  local candidates = #alive > 0 and alive or dead

  if #candidates == 1 then
    return candidates[1]
  end

  -- Sort by startedAt descending for display and fallback
  table.sort(candidates, function(a, b)
    return (a.startedAt or 0) > (b.startedAt or 0)
  end)

  -- Multiple: use vim.ui.select
  return nil, candidates
end

-- Format a session for the picker
local function format_session_label(session)
  local time_str = ''
  if session.startedAt then
    time_str = os.date('%Y-%m-%d %H:%M', session.startedAt / 1000)
  end
  local name = session.name or session.sessionId
  local status = pid_alive(session.pid) and '[active]' or '[ended]'
  return string.format('%s  %s  %s', time_str, status, name)
end

-- Main discovery function. Returns session info or nil.
-- If multiple candidates, prompts with vim.ui.select and calls callback.
local function discover_session(explicit_id, callback)
  if explicit_id and explicit_id ~= '' then
    local jsonl_path = find_jsonl_path(explicit_id)
    if jsonl_path then
      callback({ sessionId = explicit_id }, jsonl_path)
    else
      vim.notify('Session not found: ' .. explicit_id, vim.log.levels.ERROR)
    end
    return
  end

  local all_sessions = read_session_metadata()

  -- Primary: current buffer
  local session = discover_from_current_buffer(all_sessions)
  if session then
    local jsonl_path = find_jsonl_path(session.sessionId)
    if jsonl_path then
      callback(session, jsonl_path)
      return
    end
  end

  -- Fallback: cwd match
  local single, candidates = discover_from_cwd(all_sessions)
  if single then
    local jsonl_path = find_jsonl_path(single.sessionId)
    if jsonl_path then
      callback(single, jsonl_path)
      return
    end
  end

  if candidates and #candidates > 0 then
    vim.ui.select(candidates, {
      prompt = 'Select Claude Code session:',
      format_item = format_session_label,
    }, function(choice)
      if choice then
        local jsonl_path = find_jsonl_path(choice.sessionId)
        if jsonl_path then
          callback(choice, jsonl_path)
        else
          vim.notify('JSONL not found for session: ' .. choice.sessionId, vim.log.levels.ERROR)
        end
      end
    end)
    return
  end

  vim.notify('No Claude Code session found for this directory', vim.log.levels.WARN)
end

-- ---------------------------------------------------------------------------
-- JSONL Parser
-- ---------------------------------------------------------------------------

-- Extract a short summary for a tool_use block
local function tool_summary(tool)
  local name = tool.name or '?'
  local input = tool.input or {}

  if name == 'Read' then
    return name .. ' ' .. (input.file_path or '')
  elseif name == 'Edit' then
    return name .. ' ' .. (input.file_path or '')
  elseif name == 'Write' then
    return name .. ' ' .. (input.file_path or '')
  elseif name == 'Bash' then
    return name .. ' ' .. (input.description or input.command or ''):sub(1, 60)
  elseif name == 'Grep' then
    return name .. ' ' .. (input.pattern or '')
  elseif name == 'Glob' then
    return name .. ' ' .. (input.pattern or '')
  elseif name == 'Agent' then
    return name .. ' (' .. (input.subagent_type or 'general') .. ') ' .. (input.description or '')
  elseif name == 'ToolSearch' then
    return name .. ' ' .. (input.query or '')
  else
    return name
  end
end

-- Parse the JSONL file and return a list of conversation turns
-- Each turn is: { role = 'user'|'assistant', blocks = { ... } }
-- Block types:
--   { type='text', text='...' }
--   { type='tool_use', summary='...', input='...', result='...', result_lines=N }
--   { type='thinking' }
local function parse_jsonl(filepath)
  local lines = vim.fn.readfile(filepath)
  if not lines then return {} end

  -- First pass: collect all entries
  local entries = {}
  for _, line in ipairs(lines) do
    if line ~= '' then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and obj then
        table.insert(entries, obj)
      end
    end
  end

  -- Second pass: group assistant messages by message ID and collect tool results
  -- We need to:
  -- 1. Group assistant content blocks by message ID (they span multiple JSONL lines)
  -- 2. Collect tool_result entries (which come as user messages) keyed by tool_use_id
  local assistant_groups = {} -- msg_id -> { order=N, blocks={} }
  local tool_results = {}     -- tool_use_id -> { content='...', is_error=bool }
  local order = 0

  for _, entry in ipairs(entries) do
    local etype = entry.type
    local msg = entry.message or {}
    local content = msg.content

    if etype == 'assistant' and type(content) == 'table' then
      local msg_id = msg.id or entry.uuid or tostring(order)
      if not assistant_groups[msg_id] then
        order = order + 1
        assistant_groups[msg_id] = { order = order, blocks = {} }
      end
      for _, block in ipairs(content) do
        table.insert(assistant_groups[msg_id].blocks, block)
      end

    elseif etype == 'user' and type(content) == 'table' then
      -- Tool result messages
      for _, block in ipairs(content) do
        if block.type == 'tool_result' and block.tool_use_id then
          local result_text = ''
          if type(block.content) == 'string' then
            result_text = block.content
          elseif type(block.content) == 'table' then
            -- content can be an array of {type='text', text='...'}
            local parts = {}
            for _, part in ipairs(block.content) do
              if type(part) == 'table' and part.text then
                table.insert(parts, part.text)
              elseif type(part) == 'string' then
                table.insert(parts, part)
              end
            end
            result_text = table.concat(parts, '\n')
          end
          tool_results[block.tool_use_id] = {
            content = result_text,
            is_error = block.is_error or false,
          }
        end
      end
    end
  end

  -- Third pass: build conversation turns in order
  local turns = {}

  for _, entry in ipairs(entries) do
    local etype = entry.type
    local msg = entry.message or {}
    local content = msg.content

    -- User messages with string content = real prompts
    if etype == 'user' and type(content) == 'string' and content ~= '' then
      table.insert(turns, {
        role = 'user',
        blocks = { { type = 'text', text = content } },
      })

    -- Assistant messages: only process on first encounter of each msg_id
    elseif etype == 'assistant' and type(content) == 'table' then
      local msg_id = msg.id or entry.uuid or ''
      local group = assistant_groups[msg_id]
      if group and group.order then
        -- Process this group and clear the order to avoid duplicates
        local blocks = {}
        for _, block in ipairs(group.blocks) do
          if block.type == 'text' and block.text and block.text ~= '' then
            table.insert(blocks, { type = 'text', text = block.text })

          elseif block.type == 'tool_use' then
            local tool_id = block.id or ''
            local result = tool_results[tool_id]
            local result_text = result and result.content or ''
            local result_line_list = vim.split(result_text, '\n', { plain = true })
            table.insert(blocks, {
              type = 'tool_use',
              summary = tool_summary(block),
              input = vim.json.encode(block.input or {}),
              result = result_text,
              result_lines = #result_line_list,
              is_error = result and result.is_error or false,
            })

          end
        end

        if #blocks > 0 then
          table.insert(turns, {
            role = 'assistant',
            blocks = blocks,
          })
        end
        group.order = nil -- mark as consumed
      end
    end
  end

  return turns
end

-- ---------------------------------------------------------------------------
-- Renderer
-- ---------------------------------------------------------------------------

local MAX_TOOL_RESULT_LINES = 20

-- Render conversation turns into a list of lines and a parallel fold-level table
local function render_turns(turns)
  local lines = {}
  local fold_levels = {}

  local function add(text, level)
    table.insert(lines, text)
    table.insert(fold_levels, level)
  end

  local prev_role = nil

  for _, turn in ipairs(turns) do
    if turn.role == 'user' then
      add('── User ──────────────────────────────────────', 0)
      for _, block in ipairs(turn.blocks) do
        if block.type == 'text' then
          for _, tl in ipairs(vim.split(block.text, '\n', { plain = true })) do
            add(tl, 0)
          end
        end
      end
      add('', 0)

    elseif turn.role == 'assistant' then
      if prev_role ~= 'assistant' then
        add('── Assistant ──────────────────────────────────', 0)
      end
      for _, block in ipairs(turn.blocks) do
        if block.type == 'text' then
          for _, tl in ipairs(vim.split(block.text, '\n', { plain = true })) do
            add(tl, 0)
          end

        elseif block.type == 'tool_use' then
          -- Summary line (always visible, starts the fold)
          local err_marker = block.is_error and ' [ERROR]' or ''
          add('  ▶ Tool: ' .. block.summary .. err_marker, '>2')
          -- Expanded content (fold level 2)
          -- Input (truncated)
          local input_preview = block.input:sub(1, 200)
          if #block.input > 200 then input_preview = input_preview .. '...' end
          add('    Input: ' .. input_preview, 2)
          -- Result
          if block.result ~= '' then
            local result_lines = vim.split(block.result, '\n', { plain = true })
            local showing = math.min(#result_lines, MAX_TOOL_RESULT_LINES)
            if #result_lines > MAX_TOOL_RESULT_LINES then
              add('    Result (' .. #result_lines .. ' lines, showing first ' .. showing .. '):', 2)
            else
              add('    Result:', 2)
            end
            for i = 1, showing do
              add('    ' .. result_lines[i], 2)
            end
            if #result_lines > MAX_TOOL_RESULT_LINES then
              add('    ...', 2)
            end
          else
            add('    Result: (empty)', 2)
          end
          add('', 0)

        end
      end
      add('', 0)
    end

    prev_role = turn.role
  end

  return lines, fold_levels
end

-- ---------------------------------------------------------------------------
-- Buffer Management
-- ---------------------------------------------------------------------------

-- Find an existing session tree buffer for a given session ID
local function find_existing_buffer(session_id)
  local target_name = 'claude-code-session-tree://' .. session_id
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == target_name then
        return bufnr
      end
    end
  end
  return nil
end

-- Store fold levels per buffer for foldexpr
M._fold_levels = {}

-- Store file watchers per buffer
M._watchers = {}

-- Store jsonl paths per buffer for re-rendering
M._jsonl_paths = {}

-- The foldexpr function (called by Neovim for each line)
function M.foldexpr(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local levels = M._fold_levels[bufnr]
  if not levels or not levels[lnum] then
    return '0'
  end
  local level = levels[lnum]
  if type(level) == 'string' then
    return level -- e.g. '>2'
  end
  return tostring(level)
end

-- Render a session into a buffer
local function render_session(bufnr, jsonl_path)
  local turns = parse_jsonl(jsonl_path)
  local lines, fold_levels = render_turns(turns)

  -- Store fold levels
  M._fold_levels[bufnr] = fold_levels

  -- Save cursor and fold state
  local cursor = nil
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    cursor = vim.api.nvim_win_get_cursor(win)
  end

  -- Write lines
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace('claude_session_tree')
  for i, line in ipairs(lines) do
    if line:match('^── User ──') then
      vim.api.nvim_buf_add_highlight(bufnr, ns, 'ClaudeSessionUser', i - 1, 0, -1)
    elseif line:match('^── Assistant ──') then
      vim.api.nvim_buf_add_highlight(bufnr, ns, 'ClaudeSessionAssistant', i - 1, 0, -1)
    elseif line:match('^  ▶ Tool:') then
      vim.api.nvim_buf_add_highlight(bufnr, ns, 'ClaudeSessionTool', i - 1, 0, -1)
    elseif line:match('%[ERROR%]') then
      vim.api.nvim_buf_add_highlight(bufnr, ns, 'ClaudeSessionError', i - 1, 0, -1)
    end
  end

  -- Restore cursor
  if cursor and win ~= -1 then
    local max_line = vim.api.nvim_buf_line_count(bufnr)
    if cursor[1] > max_line then cursor[1] = max_line end
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
  end
end

-- Create or switch to a session tree buffer
local function open_session(session, jsonl_path)
  local session_id = session.sessionId
  local buf_name = 'claude-code-session-tree://' .. session_id

  -- Check for existing buffer
  local bufnr = find_existing_buffer(session_id)
  if bufnr then
    -- Re-render with latest data
    vim.api.nvim_set_current_buf(bufnr)
    render_session(bufnr, jsonl_path)
    return
  end

  -- Create new scratch buffer
  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, buf_name)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].buflisted = true
  vim.bo[bufnr].modifiable = false

  -- Switch to the buffer in current window
  vim.api.nvim_set_current_buf(bufnr)

  -- Set fold options (must be done after buffer is in a window)
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = "v:lua.require'claude-code-session-tree'.foldexpr(v:lnum)"
  vim.wo.foldlevel = 1
  vim.wo.foldenable = true
  vim.wo.foldtext = ''
  vim.wo.signcolumn = 'no'
  vim.wo.relativenumber = false
  vim.wo.foldcolumn = '0'

  -- Set filetype for syntax
  vim.bo[bufnr].filetype = 'markdown'

  -- Store jsonl path
  M._jsonl_paths[bufnr] = jsonl_path

  -- Render
  render_session(bufnr, jsonl_path)

  -- Start file watcher
  M._start_watcher(bufnr, jsonl_path)
end

-- ---------------------------------------------------------------------------
-- File Watcher
-- ---------------------------------------------------------------------------

function M._start_watcher(bufnr, jsonl_path)
  -- Clean up any existing watcher for this buffer
  if M._watchers[bufnr] then
    M._watchers[bufnr]:stop()
    M._watchers[bufnr] = nil
  end

  local watcher = vim.uv.new_fs_event()
  if not watcher then return end

  local debounce_timer = nil
  local DEBOUNCE_MS = 500

  watcher:start(jsonl_path, {}, function(err)
    if err then return end
    -- Debounce: reset timer on each change
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer:close()
    end
    debounce_timer = vim.uv.new_timer()
    debounce_timer:start(DEBOUNCE_MS, 0, function()
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          render_session(bufnr, jsonl_path)
        else
          -- Buffer gone, stop watching
          watcher:stop()
          M._watchers[bufnr] = nil
        end
      end)
    end)
  end)

  M._watchers[bufnr] = watcher

  -- Clean up watcher when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = bufnr,
    once = true,
    callback = function()
      if M._watchers[bufnr] then
        M._watchers[bufnr]:stop()
        M._watchers[bufnr] = nil
      end
      M._fold_levels[bufnr] = nil
      M._jsonl_paths[bufnr] = nil
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Highlight Groups
-- ---------------------------------------------------------------------------

local function setup_highlights()
  -- Only set if not already defined by a colorscheme
  local function hl_default(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hl_default('ClaudeSessionUser', { fg = '#7aa2f7', bold = true })
  hl_default('ClaudeSessionAssistant', { fg = '#9ece6a', bold = true })
  hl_default('ClaudeSessionTool', { fg = '#e0af68' })
  hl_default('ClaudeSessionError', { fg = '#f7768e', bold = true })
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

function M.setup()
  setup_highlights()

  vim.api.nvim_create_user_command('ClaudeCodeSessionTree', function(opts)
    local session_id = opts.args ~= '' and opts.args or nil
    discover_session(session_id, open_session)
  end, {
    nargs = '?',
    desc = 'Open Claude Code session tree viewer',
  })
end

return M
