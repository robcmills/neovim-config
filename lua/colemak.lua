-- colemak adjustments

-- vim.keymap.set("n", "n", function()
--   if vim.v.searchforward ~= nil then
--       -- You're in search context
--       print("In Search Context!")
--   else
--       -- Normal context
--       print("In Normal Context!")
--   end
-- end, { desc = "New buffer" })


vim.keymap.set("n", "n", "j", { desc = "Down (j)" })
vim.keymap.set("n", "j", "n")
vim.keymap.set("n", "e", "k", { desc = "Up (k)" })
vim.keymap.set("n", "k", "e")
vim.keymap.set("n", "i", "l", { desc = "Right (l)" })
vim.keymap.set("n", "l", "i")

vim.keymap.set("x", "n", "j", { desc = "Down (j)" })
vim.keymap.set("x", "j", "n")
vim.keymap.set("x", "e", "k", { desc = "Up (k)" })
vim.keymap.set("x", "k", "e")
vim.keymap.set("x", "i", "l", { desc = "Right (l)" })
vim.keymap.set("x", "l", "i")

vim.keymap.set("n", "N", "<C-d>", { desc = "Page down" })
vim.keymap.set("n", "J", "N", { desc = "Previous search result" })
vim.keymap.set("n", "E", "<C-u>", { desc = "Page up" })

