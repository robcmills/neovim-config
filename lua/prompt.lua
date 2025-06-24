--[[
Markdown Prompt Plugin for Neovim

A simple plugin that opens a floating window with a markdown prompt buffer.
Submits prompt to OpenRouter API for LLM completion.
Streams response back to buffer.

Features:
- Opens a centered floating window with markdown syntax highlighting
- Press q to close
- Automatically enters insert mode for immediate typing
- Configurable window size and appearance
- Submit prompt to OpenRouter API for AI completion
- Autosaves prompts and responses to history directory
- Create a new prompt with :PromptNew command

Usage:
- Command :Prompt - Open a floating markdown prompt window
- Command :PromptSubmit - Submit prompt to OpenRouter API for AI completion
- Command :PromptNew - Create a new prompt (clears current buffer)

Configuration:
You can customize the plugin by calling require('prompt').setup() with options:
{
    width = 80,        -- Window width
    height = 20,       -- Window height
    border = "rounded", -- Border style
    title = " Prompt ", -- Window title
    title_pos = "center", -- Title position
    model = "anthropic/claude-3.5-sonnet", -- OpenRouter model to use
    response_delineator = "● %s ────────────", -- Format for response delineator
    history_dir = "prompt_history/", -- Directory to save chat history
    max_filename_length = 50, -- Maximum length for generated filename summaries
    window_position = "center", -- Window position: "center", "left", or "right"
}

Example:
require('prompt').setup({
    width = 100,
    height = 25,
    border = "double",
    model = "openai/gpt-4o",
    history_dir = "~/.local/share/nvim/prompt_history/",
    max_filename_length = 60,
    window_position = "right" -- Opens prompt window on the right side, full height
})

Autosave Feature:
- Automatically saves prompts and responses to files in the history directory
- Filenames use ISO datetime format (e.g., "2025-06-21T04:27:18.md")
- Saves prompt content before submitting to API
- Syncs final content (including response) when streaming completes
- Use :PromptNew to start a fresh conversation

### Todo

- Scroll delineator to top when submitting prompt
- Model picker
- Add support for chats longer than one question and answer
- Resize window when buffer lines length exceeds window height
- Resize window when buffer longest line width exceeds window width
- Move state into object
- Disable buffer editing when streaming response
- Enable cancellation of streaming request
- UI
- Tests
- Quitting nvim while prompt window is open throws many errors

--]]

local M = {}

local OPENROUTER_API_KEY = os.getenv('OPENROUTER_API_KEY')
local OPENROUTER_API_V1_CHAT_COMPLETIONS_URL = 'https://openrouter.ai/api/v1/chat/completions'

local config = {
  width = 80,
  height = 20,
  border = "rounded",
  title = " prompt.md ",
  title_pos = "right",
  model = "anthropic/claude-sonnet-4",
  response_delineator = "● %s ────────────",
  history_dir = "~/.local/share/nvim/prompt_history/",
  max_filename_length = 50,
  window_position = "right", -- "center", "left", or "right"
}

-- State
local prompt_bufnr = nil
local prompt_winid = nil
local current_chat_filename = nil

-- Utility functions

local function get_history_dir()
  local dir = config.history_dir
  if string.sub(dir, 1, 1) == "~" then
    dir = vim.fn.expand(dir)
  end
  return dir
end

local function ensure_history_dir()
  local dir = get_history_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

local function get_timestamp_filename()
  local timestamp = os.date("%Y-%m-%dT%H:%M:%S")
  return timestamp .. ".md"
end

local function save_chat_history(chat_id, content)
  ensure_history_dir()
  local filepath = get_history_dir() .. chat_id
  local file = io.open(filepath, "w")
  if file then
    file:write(content)
    file:close()
  else
    vim.notify("Failed to save chat history to " .. filepath, vim.log.levels.ERROR)
  end
end

local function get_buffer_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

local function sync_chat_history()
  if not current_chat_filename then
    return
  end

  if not prompt_bufnr or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
    return
  end

  local content = get_buffer_content(prompt_bufnr)
  save_chat_history(current_chat_filename, content)
end

local function get_window_config()
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  local position = config.window_position or "center"

  local width, height, col, row

  if position == "left" then
    width = config.width
    height = screen_height - 4 -- Full height minus borders
    col = 0
    row = 0
  elseif position == "right" then
    width = config.width
    height = screen_height - 4 -- Full height minus borders
    col = screen_width - width
    row = 0
  else
    -- Default to center positioning
    width = config.width
    height = config.height
    col = math.floor((screen_width - width) / 2)
    row = math.floor((screen_height - height) / 2)
  end

  return {
    border = config.border,
    col = col,
    footer = string.format(" Model: %s ", config.model),
    height = height,
    relative = "editor",
    row = row,
    style = "minimal",
    title = config.title,
    title_pos = config.title_pos,
    width = width,
  }
end

local function create_markdown_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_name(bufnr, "prompt://markdown")
  return bufnr
end

local function get_or_create_prompt_buffer()
  -- If we already have a valid prompt buffer, return it
  if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
    return prompt_bufnr
  end

  -- Otherwise create a new one
  prompt_bufnr = create_markdown_buffer()
  return prompt_bufnr
end

local function setup_keymaps(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set("n", "q", function()
    M.close_prompt()
  end, opts)
end

local function setup_autocommands(bufnr)
  local group = vim.api.nvim_create_augroup("PromptWindow", { clear = true })

  -- Close window when leaving it (but don't delete buffer)
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.close_prompt()
    end,
  })
end

-- OpenRouter API functions

local function make_openrouter_request(opts)
  if not OPENROUTER_API_KEY then
    vim.notify("OPENROUTER_API_KEY environment variable not set", vim.log.levels.ERROR)
    return
  end

  local request_body = vim.json.encode({
    model = opts.model,
    messages = opts.messages,
    stream = opts.stream,
  })

  local headers = {
    "Authorization: Bearer " .. OPENROUTER_API_KEY,
    "HTTP-Referer: robcmills.net",
    "X-Title: markdown-prompt.nvim",
    "Content-Type: application/json",
  }

  local curl_args = {
    "-X", "POST",
    "-H", table.concat(headers, " -H "),
    "-d", request_body,
    "--silent", -- Suppress progress output
    "--no-buffer",
    OPENROUTER_API_V1_CHAT_COMPLETIONS_URL
  }

  local buffer = ""

  local function handle_stdout(err, data)
    if err then print('handle_stdout err: ' .. err) end

    if not data then
      print('handle_stdout: no data')
      return
    end

    buffer = buffer .. data

    if opts.stream then
      -- Process complete lines from buffer for streaming
      while true do
        local line_end = string.find(buffer, "\n")
        if not line_end then break end

        local line = string.sub(buffer, 1, line_end - 1)
        buffer = string.sub(buffer, line_end + 1)

        line = vim.trim(line)

        if string.sub(line, 1, 6) == "data: " then
          local json = string.sub(line, 7)
          if json == "[DONE]" then
            return
          end

          local success, parsed = pcall(vim.json.decode, json)
          if success and parsed.choices and parsed.choices[1] and parsed.choices[1].delta and parsed.choices[1].delta.content then
            if opts.on_delta_content then
              opts.on_delta_content(parsed.choices[1].delta.content)
            end
          else
            print('handle_stdout: failed to parse json data: ' .. json)
          end
        elseif string.sub(line, 1, 1) == ":" then
          -- Ignore SSE comments
        end
      end
    end
  end

  local function handle_stderr(err, data)
    if err then print('handle_stderr err: ' .. err) end
    if data then print('handle_stderr data: ' .. data) end
  end

  local function on_exit(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify("OpenRouter API request failed with exit code: " .. obj.code, vim.log.levels.ERROR)
        return
      end

      if opts.on_success then
        if opts.stream then
          opts.on_success()
        else
          -- For non-streaming requests, parse the JSON response and extract content
          local success, parsed = pcall(vim.json.decode, buffer)
          if success and parsed.choices and parsed.choices[1] and parsed.choices[1].message and parsed.choices[1].message.content then
            opts.on_success(parsed.choices[1].message.content)
          else
            vim.notify("Failed to parse OpenRouter API response", vim.log.levels.ERROR)
          end
        end
      end
    end)
  end

  vim.system({ "curl", unpack(curl_args) }, {
    stdout_buffered = false,
    stderr_buffered = false,
    stdout = handle_stdout,
    stderr = handle_stderr,
  }, on_exit)
end

local function add_response_delineator(bufnr, model)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    print('add_response_delineator: buffer not valid')
    return
  end

  local content = get_buffer_content(bufnr)
  local delineator = string.format(config.response_delineator, model)

  local new_content = content .. "\n\n" .. delineator .. "\n\n"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, "\n"))
end

local function append_to_buffer(bufnr, text)
  vim.schedule(function()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      print('append_to_buffer: buffer not valid')
      return
    end

    if not vim.bo[bufnr].modifiable then
      print('append_to_buffer: buffer not modifiable')
      return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    if #lines == 0 then lines = { "" } end

    local current_line = lines[#lines]
    local text_parts = vim.split(text, "\n")

    -- Handle the first part (append to current line)
    if #text_parts > 0 then
      lines[#lines] = current_line .. text_parts[1]
    end

    -- Handle remaining parts (each becomes a new line)
    for i = 2, #text_parts do
      table.insert(lines, text_parts[i])
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end)
end

local function rename_file(old_path, new_path)
  local success = os.rename(old_path, new_path)
  if not success then
    vim.notify("Failed to rename file from " .. old_path .. " to " .. new_path, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function sanitize_filename(text)
  -- Remove punctuation and convert to lowercase
  local sanitized = string.lower(text)
  -- Replace spaces and other separators with hyphens
  sanitized = string.gsub(sanitized, "[%s%p]+", "-")
  -- Remove multiple consecutive hyphens
  sanitized = string.gsub(sanitized, "-+", "-")
  -- Remove leading and trailing hyphens
  sanitized = string.gsub(sanitized, "^%-+", "")
  sanitized = string.gsub(sanitized, "%-+$", "")
  -- Clip to max length
  if #sanitized > config.max_filename_length then
    sanitized = string.sub(sanitized, 1, config.max_filename_length)
    -- Ensure we don't end with a hyphen
    sanitized = string.gsub(sanitized, "%-+$", "")
  end
  return sanitized
end

local function add_prompt_summary(filename, prompt)
  local summary_prompt = string.format([[
Summarize the following Prompt in a single, very short title.
Format it for a filename, in kebab-case, no spaces, and no punctuation.
Respond with only the title and nothing else.

<Prompt>
%s
</Prompt>
]], prompt)

  local messages = {
    { role = "user", content = summary_prompt }
  }

  local function on_success(summary)
    if not summary then
      vim.notify("Failed to generate prompt summary", vim.log.levels.ERROR)
      return
    end

    -- Sanitize the summary for filename use
    local sanitized_summary = sanitize_filename(summary)

    if sanitized_summary == "" then
      vim.notify("Generated summary is empty, keeping original filename", vim.log.levels.WARN)
      return
    end

    -- Create new filename
    local base_name = string.gsub(filename, "%.md$", "")
    local new_filename = base_name .. "-" .. sanitized_summary .. ".md"

    -- Rename the file
    local old_path = get_history_dir() .. filename
    local new_path = get_history_dir() .. new_filename

    if rename_file(old_path, new_path) then
      current_chat_filename = new_filename
      vim.notify("Renamed prompt file to: " .. new_filename, vim.log.levels.INFO)
    end
  end

  make_openrouter_request({
    messages = messages,
    model = config.model,
    stream = false,
    on_success = on_success
  })
end

function M.submit_prompt()
  if not prompt_bufnr or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
    vim.notify("No prompt buffer found. Use :Prompt first.", vim.log.levels.WARN)
    return
  end

  local buffer_content = get_buffer_content(prompt_bufnr)
  if buffer_content == "" then
    vim.notify("Prompt buffer is empty.", vim.log.levels.WARN)
    return
  end

  if current_chat_filename == nil then
    current_chat_filename = get_timestamp_filename()
  end
  save_chat_history(current_chat_filename, buffer_content)
  add_prompt_summary(current_chat_filename, buffer_content)

  add_response_delineator(prompt_bufnr, config.model)

  local messages = {
    { role = "user", content = buffer_content }
  }

  make_openrouter_request({
    messages = messages,
    model = config.model,
    stream = true,
    on_success = function()
      -- Sync the final content including response to history file
      sync_chat_history()
      if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
        vim.bo[prompt_bufnr].modifiable = true
      end
    end,
    on_delta_content = function(content)
      append_to_buffer(prompt_bufnr, content)
    end
  })
end

-- Public functions

function M.open_prompt()
  if prompt_winid and vim.api.nvim_win_is_valid(prompt_winid) then
    M.close_prompt()
  end

  -- Get or create the prompt buffer (this will reuse existing content)
  local bufnr = get_or_create_prompt_buffer()

  local win_config = get_window_config()
  prompt_winid = vim.api.nvim_open_win(bufnr, true, win_config)

  vim.wo[prompt_winid].wrap = true
  vim.wo[prompt_winid].linebreak = true
  vim.wo[prompt_winid].cursorline = true

  setup_keymaps(bufnr)
  setup_autocommands(bufnr)

  if vim.api.nvim_buf_line_count(bufnr) <= 1 then
    vim.cmd("startinsert")
  end
end

function M.close_prompt()
  if prompt_winid and vim.api.nvim_win_is_valid(prompt_winid) then
    vim.api.nvim_win_close(prompt_winid, true)
    prompt_winid = nil
  end
end

function M.clear_prompt()
  if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
    vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, {})
  end
end

function M.load_prompt_history()
  ensure_history_dir()
  local history_dir = get_history_dir()

  -- Get list of markdown files in history directory
  local files = vim.fn.globpath(history_dir, "*.md", false, true)

  if #files == 0 then
    vim.notify("No prompt history found in " .. history_dir, vim.log.levels.INFO)
    return
  end

  -- Extract just the filenames for display
  local file_choices = {}
  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t")
    table.insert(file_choices, {
      filename = filename,
      filepath = filepath,
      display = filename
    })
  end

  -- Sort by filename (which includes timestamp) in descending order (newest first)
  table.sort(file_choices, function(a, b)
    return a.filename > b.filename
  end)

  vim.ui.select(file_choices, {
    prompt = "Select a prompt from history:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    -- Read the selected file
    local file = io.open(choice.filepath, "r")
    if not file then
      vim.notify("Failed to read file: " .. choice.filepath, vim.log.levels.ERROR)
      return
    end

    local content = file:read("*all")
    file:close()

    -- Load content into prompt buffer
    if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      vim.api.nvim_buf_set_lines(prompt_bufnr, 0, -1, false, vim.split(content, "\n"))
      current_chat_filename = choice.filename
      vim.notify("Loaded prompt from: " .. choice.filename, vim.log.levels.INFO)

      -- Open the prompt window if not already open
      if not prompt_winid or not vim.api.nvim_win_is_valid(prompt_winid) then
        M.open_prompt()
      end
    else
      vim.notify("Prompt buffer not available", vim.log.levels.ERROR)
    end
  end)
end

-- Setup function
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end
end

-- Create user commands
vim.api.nvim_create_user_command("Prompt", function()
  M.open_prompt()
end, { desc = "Open a floating markdown prompt window" })

vim.api.nvim_create_user_command("PromptSubmit", function()
  M.submit_prompt()
end, { desc = "Submit prompt to OpenRouter API for AI completion" })

vim.api.nvim_create_user_command("PromptNew", function()
  M.clear_prompt()
  current_chat_filename = nil
  -- Open the prompt window if not already open
  if not prompt_winid or not vim.api.nvim_win_is_valid(prompt_winid) then
    M.open_prompt()
  end
end, { desc = "Create a new prompt" })

vim.api.nvim_create_user_command("PromptHistory", function()
  M.load_prompt_history()
end, { desc = "Browse and load prompt history" })

return M
