require('avante_lib').load()
require('avante').setup ({
  hints = { enabled = false },
  windows = {
    width = 50, -- default % based on available width
    sidebar_header = {
      align = "center", -- left, center, right for title
      rounded = false,
    },
  },
})
