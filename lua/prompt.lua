--[[
Prompt Plugin for Neovim

A simple plugin that opens a floating window with a markdown buffer.

Features:
- Opens a centered floating window with markdown syntax highlighting
- Press q to close (deletes the buffer)
- Automatically enters insert mode for immediate typing
- Configurable window size and appearance

Usage:
- Command: :Prompt
- Keybinding: <leader>P (capital P)

Configuration:
You can customize the plugin by calling require('prompt').setup() with options:
{
    width = 80,        -- Window width
    height = 20,       -- Window height  
    border = "rounded", -- Border style
    title = " Prompt ", -- Window title
    title_pos = "center" -- Title position
}

Example:
require('prompt').setup({
    width = 100,
    height = 25,
    border = "double"
})
--]]

local M = {}

-- Configuration
local config = {
    width = 80,
    height = 20,
    border = "rounded",
    title = " prompt.md ",
    title_pos = "center",
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

-- Create user command
vim.api.nvim_create_user_command("Prompt", function()
    M.open_prompt()
end, { desc = "Open a floating markdown prompt window" })

return M
