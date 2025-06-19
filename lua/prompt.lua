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

Usage:
- Command :Prompt
- Command :PromptSubmit

Configuration:
You can customize the plugin by calling require('prompt').setup() with options:
{
    width = 80,        -- Window width
    height = 20,       -- Window height  
    border = "rounded", -- Border style
    title = " Prompt ", -- Window title
    title_pos = "center", -- Title position
    model = "anthropic/claude-3.5-sonnet", -- OpenRouter model to use
    response_delineator = "● %s ────────────" -- Format for response delineator
}

Example:
require('prompt').setup({
    width = 100,
    height = 25,
    border = "double",
    model = "openai/gpt-4o"
})

### Todo

- Don't delete buffer when leaving window
- Flatten stdout handler
- Move state into object
- Disable buffer editing when streaming response
- Enable cancellation of streaming request
- Persist chats
- Model picker
- UI for configuration and key bindings
- Tests

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
    model = "openai/chatgpt-4o-latest",
    response_delineator = "● %s ────────────",
}

-- State
local prompt_bufnr = nil
local prompt_winid = nil

-- Utility functions

local function center_window()
    local width = config.width
    local height = config.height

    local screen_width = vim.o.columns
    local screen_height = vim.o.lines

    local col = math.floor((screen_width - width) / 2)
    local row = math.floor((screen_height - height) / 2)

    return {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal",
        border = config.border,
        title = config.title,
        title_pos = config.title_pos,
    }
end

local function create_markdown_buffer()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_name(bufnr, "prompt://markdown")
    return bufnr
end

local function setup_keymaps(bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set("n", "q", function()
        M.close_prompt()
    end, opts)
end

local function setup_autocommands(bufnr)
    local group = vim.api.nvim_create_augroup("PromptWindow", { clear = true })

    -- Close window when buffer is deleted
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = bufnr,
        callback = function()
            if prompt_winid and vim.api.nvim_win_is_valid(prompt_winid) then
                vim.api.nvim_win_close(prompt_winid, true)
                prompt_winid = nil
            end
        end,
    })

    -- Close window when leaving it
    vim.api.nvim_create_autocmd("WinLeave", {
        group = group,
        buffer = bufnr,
        callback = function()
            M.close_prompt()
        end,
    })
end

-- OpenRouter API functions

local function get_buffer_content(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
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

        if #lines == 0 then lines = {""} end

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

    add_response_delineator(prompt_bufnr, config.model)

    local messages = {
        {role = "user", content = content}
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
        "--silent",  -- Suppress progress output
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
                    -- Re-enable buffer editing
                    vim.schedule(function()
                        if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
                            vim.bo[prompt_bufnr].modifiable = true
                        end
                    end)
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
            -- vim.schedule(function()
            --     vim.notify("OpenRouter API error: " .. data, vim.log.levels.ERROR)
            -- end)
    end

    local function on_exit(obj)
        vim.schedule(function()
            if obj.code ~= 0 then
                vim.notify("OpenRouter API request failed with exit code: " .. obj.code, vim.log.levels.ERROR)
            end
            if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
                vim.bo[prompt_bufnr].modifiable = true
            end
        end)
    end


    -- Make buffer read-only during streaming
    -- vim.bo[prompt_bufnr].modifiable = false

    vim.system({"curl", unpack(curl_args)}, {
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

    prompt_bufnr = create_markdown_buffer()

    local win_opts = center_window()
    prompt_winid = vim.api.nvim_open_win(prompt_bufnr, true, win_opts)

    vim.wo[prompt_winid].wrap = true
    vim.wo[prompt_winid].linebreak = true
    vim.wo[prompt_winid].cursorline = true

    setup_keymaps(prompt_bufnr)
    setup_autocommands(prompt_bufnr)

    vim.cmd("startinsert")
end

function M.close_prompt()
    if prompt_winid and vim.api.nvim_win_is_valid(prompt_winid) then
        vim.api.nvim_win_close(prompt_winid, true)
        prompt_winid = nil
    end

    if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
        vim.api.nvim_buf_delete(prompt_bufnr, { force = true })
        prompt_bufnr = nil
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

return M
