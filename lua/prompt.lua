--[[

                                                              ██
██████ █████ ██████ ██████████ ██████ ██████   ██████████ ██████
██  ██ ██    ██  ██ ██  ██  ██ ██  ██   ██     ██  ██  ██ ██  ██
██████ ██    ██████ ██  ██  ██ ██████   ██  ██ ██  ██  ██ ██████
██                             ██

Markdown Prompt Plugin for Neovim

Enables prompting from a markdown buffer.
Submits prompts to OpenRouter API for LLM completion.
Streams response directly to buffer.

### Todo

- Add more providers support
- Add token counts and costs stats
- Add sqlite db for storing more data
- Add split window support (instead of floating window)
- Enable multiple prompts simultaneously (just use files in history_dir,
  instead of a single shared buffer)
- Model picker configurable format
- Add leaderboard sorting to model picker
- Add support for chats longer than one question and answer
- Add support for thinking models
- Add support for attaching files
- Move state into object
- Disable buffer editing when streaming response
- Enable cancellation of streaming request
- UI
- Tests
- Add "inline" prompts (meta+k) for code edits
- Add agent mode?
- Add custom markdown formatting

--]]

local M = {}

local OPENROUTER_API_KEY = os.getenv('OPENROUTER_API_KEY')
local OPENROUTER_API_V1_CHAT_COMPLETIONS_URL = 'https://openrouter.ai/api/v1/chat/completions'
local OPENROUTER_API_V1_MODELS_URL = 'https://openrouter.ai/api/v1/models'

local config = {
  chat_delineator = "● %s:",
  history_date_format = "%Y-%m-%dT%H:%M:%S",
  history_dir = "~/.local/share/nvim/prompt_history/",
  max_filename_length = 75,
  model = "anthropic/claude-sonnet-4",
  models_path = "~/.local/share/nvim/prompt_models.json",
}

-- State
local prompt_bufnr = nil
local prompt_winid = nil

-- Utility functions

local function get_history_dir()
  local dir = config.history_dir
  if string.sub(dir, 1, 1) == "~" then
    dir = vim.fn.expand(dir)
  end
  return dir
end

local function get_models_path()
  local path = config.models_path
  if string.sub(path, 1, 1) == "~" then
    path = vim.fn.expand(path)
  end
  return path
end

local function ensure_history_dir()
  local dir = get_history_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

local function get_timestamp_filename()
  local timestamp = os.date(config.history_date_format)
  return timestamp .. ".md"
end

local function get_buffer_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
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

    if not data then return end

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

local function add_chat_delineator(bufnr, role)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    print('add_chat_delineator: buffer not valid')
    return
  end

  local delineator = string.format(config.chat_delineator, role)
  local new_content = "\n" .. delineator .. "\n\n"
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(new_content, "\n"))
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
  end)
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

local function get_prompt_summary(filename, prompt, callback)
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

    if callback then callback(new_filename) end

  end

  make_openrouter_request({
    messages = messages,
    model = config.model,
    stream = false,
    on_success = on_success
  })
end

local function parse_messages_from_chat_buffer(buffer_content)
  local messages = {}
  local delineator_pattern = "^" .. string.gsub(config.chat_delineator, "%%s", "(.+)") .. "$"

  -- Split content by lines for processing
  local lines = vim.split(buffer_content, "\n")
  local current_message = {
    role = "user", -- default role for first message
    content = ""
  }
  local content_lines = {}

  for _, line in ipairs(lines) do
    -- Check if this line matches the delineator pattern
    local role_match = string.match(line, delineator_pattern)
    if role_match then
      -- Save current message if it has content
      if #content_lines > 0 then
        current_message.content = vim.trim(table.concat(content_lines, "\n"))
        if current_message.content ~= "" then
          table.insert(messages, current_message)
        end
      end

      -- Start new message
      local role = vim.trim(role_match)
      -- Validate role
      if not vim.tbl_contains({"user", "assistant", "system", "developer", "tool"}, role) then
        role = "assistant"
      end

      current_message = { role = role, content = "" }
      content_lines = {}
    else
      -- Add line to current message content
      table.insert(content_lines, line)
    end
  end

  -- Add final message if it has content
  if #content_lines > 0 then
    current_message.content = vim.trim(table.concat(content_lines, "\n"))
    if current_message.content ~= "" then
      table.insert(messages, current_message)
    end
  end

  return messages
end

function M.submit_chat()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local buffer_content = get_buffer_content(current_bufnr)

  if buffer_content == "" then
    vim.notify("Buffer is empty.", vim.log.levels.WARN)
    return
  end

  local messages = parse_messages_from_chat_buffer(buffer_content)

  if #messages == 0 then
    vim.notify("No valid messages found in buffer.", vim.log.levels.WARN)
    return
  end

  local current_filename = vim.fn.expand("%:t")
  local datetime_filename = get_timestamp_filename()
  if string.len(current_filename) == string.len(datetime_filename) then
    -- Get first user message for summary
    local first_user_message = nil
    for _, message in ipairs(messages) do
      if message.role == "user" then
        first_user_message = message.content
        break
      end
    end

    if first_user_message then
      local callback = function(summary_filename)
        vim.api.nvim_buf_set_name(
          current_bufnr,
          get_history_dir() .. summary_filename
        )
        vim.cmd("write")
      end
      get_prompt_summary(current_filename, first_user_message, callback)
    end
  end

  add_chat_delineator(current_bufnr, config.model)

  make_openrouter_request({
    messages = messages,
    model = config.model,
    stream = true,
    on_success = function()
      add_chat_delineator(current_bufnr, 'user')
      vim.cmd("write")
    end,
    on_delta_content = function(content)
      append_to_buffer(current_bufnr, content)
    end
  })
end

-- Public functions

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

function M.select_model()
  local models_path = get_models_path()

  -- Check if models file exists
  local file = io.open(models_path, "r")
  if not file then
    vim.notify("Models file not found: " .. models_path, vim.log.levels.ERROR)
    return
  end

  local content = file:read("*all")
  file:close()

  -- Parse JSON
  local success, models_data = pcall(vim.json.decode, content)
  if not success then
    vim.notify("Failed to parse models JSON file", vim.log.levels.ERROR)
    return
  end

  if not models_data.data or type(models_data.data) ~= "table" then
    vim.notify("Invalid models file format: missing 'data' array", vim.log.levels.ERROR)
    return
  end

  -- Sort models by created timestamp descending (most recent first)
  table.sort(models_data.data, function(a, b)
    return (a.created or 0) > (b.created or 0)
  end)

  -- Create choices for UI select
  local model_choices = {}
  for _, model in ipairs(models_data.data) do
    if model.id and model.name then
      table.insert(model_choices, {
        id = model.id,
        name = model.name,
        display = model.name
      })
    end
  end

  if #model_choices == 0 then
    vim.notify("No valid models found in models file", vim.log.levels.WARN)
    return
  end

  -- Temporarily disable the WinLeave autocommand to prevent the prompt window from closing
  local autocommand_group = vim.api.nvim_get_autocmds({ group = "PromptWindow" })
  local winleave_autocmd = nil
  for _, autocmd in ipairs(autocommand_group) do
    if autocmd.event == "WinLeave" then
      winleave_autocmd = autocmd
      break
    end
  end

  -- Disable the WinLeave autocommand if it exists
  if winleave_autocmd then
    vim.api.nvim_del_autocmd(winleave_autocmd.id)
  end

  vim.ui.select(model_choices, {
    prompt = "Select a model:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    -- Re-enable the WinLeave autocommand after the selection is made
    if winleave_autocmd and prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      vim.api.nvim_create_autocmd("WinLeave", {
        group = "PromptWindow",
        buffer = prompt_bufnr,
        callback = function()
          M.close_prompt()
        end,
      })
    end

    if not choice then
      return
    end

    config.model = choice.id
    vim.notify("Selected model: " .. choice.name, vim.log.levels.INFO)
  end)
end

function M.new_prompt()
  ensure_history_dir()
  local new_filename = get_timestamp_filename()
  local new_filepath = get_history_dir() .. new_filename

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buftype = ''
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buflisted = true
  vim.api.nvim_buf_set_name(bufnr, new_filepath)
  vim.api.nvim_win_set_buf(0, bufnr)

  vim.cmd("startinsert")
end

function M.split_prompt()
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  M.new_prompt()
end

-- Setup function
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end
end

-- Create user commands

-- V1: Floating window commands (single hidden buffer)
vim.api.nvim_create_user_command("PromptHistory", function()
  M.load_prompt_history()
end, { desc = "Browse and load prompt history" })

vim.api.nvim_create_user_command("PromptSelectModel", function()
  M.select_model()
end, { desc = "Select LLM model from available models" })

-- V2: Split window commands (normal buffer)
vim.api.nvim_create_user_command("PromptNew", function()
  M.new_prompt()
end, { desc = "Create a new prompt" })

vim.api.nvim_create_user_command("PromptSplit", function()
  M.split_prompt()
end, { desc = "Split the current window vertically and open a new prompt" })

vim.api.nvim_create_user_command("PromptSubmitChat", function()
  M.submit_chat()
end, { desc = "Submit chat buffer with parsed messages to OpenRouter API" })

return M
