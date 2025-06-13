-- splash screen

local function show_splash()
  local splash = {
    "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
    "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
    "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
    "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
    "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
    "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
    "",
    "                    Welcome to Neovim!",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, splash)
  vim.api.nvim_set_current_buf(buf)

  -- Center the content
  local win_height = vim.api.nvim_win_get_height(0)
  local splash_height = #splash
  local padding = math.floor((win_height - splash_height) / 2)

  for i = 1, padding do
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, {""})
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = show_splash,
})
