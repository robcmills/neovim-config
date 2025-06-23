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
    history_dir = "prompt_history/" -- Directory to save chat history
}

Example:
require('prompt').setup({
    width = 100,
    height = 25,
    border = "double",
    model = "openai/gpt-4o",
    history_dir = "~/.local/share/nvim/prompt_history/"
})

Autosave Feature:
- Automatically saves prompts and responses to files in the history directory
- Filenames use ISO datetime format (e.g., "2025-06-21T04:27:18.md")
- Saves prompt content before submitting to API
- Syncs final content (including response) when streaming completes
- Use :PromptNew to start a fresh conversation

### Todo

- Use llm to generate summary save file names
- Add support for chats longer than one question and answer
- Enable side panel for prompt window
- Resize window when buffer lines length exceeds window height
- Resize window when buffer longest line width exceeds window width
- Scroll delineator to top when submitting prompt
- Flatten stdout handler
- Move state into object
- Disable buffer editing when streaming response
- Enable cancellation of streaming request
- Model picker
- UI for configuration and key bindings
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
  history_dir = "prompt_history/",
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

local function center_window()
  local width = config.width
  local height = config.height

  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  local col = math.floor((screen_width - width) / 2)
  local row = math.floor((screen_height - height) / 2)

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

local function add_prompt_summary(filename, prompt)
  -- fetch summary filename
  -- rename file to filename .. '-' .. summary .. '.md'
  -- set current_chat_filename to filename-summary
end

local function submit_prompt()
  if not prompt_bufnr or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
    vim.notify("No prompt buffer found. Use :Prompt first.", vim.log.levels.WARN)
    return
  end

  if not OPENROUTER_API_KEY then
    vim.notify("OPENROUTER_API_KEY environment variable not set", vim.log.levels.ERROR)
    return
  end

  local content = get_buffer_content(prompt_bufnr)
  if content == "" then
    vim.notify("Prompt buffer is empty.", vim.log.levels.WARN)
    return
  end

  current_chat_filename = get_timestamp_filename()
  save_chat_history(current_chat_filename, content)
  add_prompt_summary(current_chat_filename, content)

  add_response_delineator(prompt_bufnr, config.model)

  local messages = {
    { role = "user", content = content }
  }

  local request_body = vim.json.encode({
    model = config.model,
    messages = messages,
    stream = true,
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

    -- Process complete lines from buffer
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
          append_to_buffer(prompt_bufnr, parsed.choices[1].delta.content)
        else
          print('handle_stdout: failed to parse json data: ' .. json)
        end
      elseif string.sub(line, 1, 1) == ":" then
        -- Ignore SSE comments
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
      else
        -- Sync the final content including response to history file
        sync_chat_history()
      end
      if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
        vim.bo[prompt_bufnr].modifiable = true
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

-- Public functions

function M.open_prompt()
  if prompt_winid and vim.api.nvim_win_is_valid(prompt_winid) then
    M.close_prompt()
  end

  -- Get or create the prompt buffer (this will reuse existing content)
  local bufnr = get_or_create_prompt_buffer()

  local win_opts = center_window()
  prompt_winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  vim.wo[prompt_winid].wrap = true
  vim.wo[prompt_winid].linebreak = true
  vim.wo[prompt_winid].cursorline = true

  setup_keymaps(bufnr)
  setup_autocommands(bufnr)

  vim.cmd("startinsert")
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
  submit_prompt()
end, { desc = "Submit prompt to OpenRouter API for AI completion" })

vim.api.nvim_create_user_command("PromptNew", function()
  M.clear_prompt()
  current_chat_filename = nil
  -- Open the prompt window if not already open
  if not prompt_winid or not vim.api.nvim_win_is_valid(prompt_winid) then
    M.open_prompt()
  end
end, { desc = "Create a new prompt" })

return M
