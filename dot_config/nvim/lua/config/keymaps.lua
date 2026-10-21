-- Global keymaps not tied to a specific plugin.
-- Plugin-specific maps (telescope, lsp, gitsigns) live with their plugin specs.
local map = vim.keymap.set

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Window resize (from old config, <Leader> is ',')
map("n", "<Leader>>", function()
  vim.cmd("vertical resize +10")
end, { desc = "Widen window" })
map("n", "<Leader><", function()
  vim.cmd("vertical resize -10")
end, { desc = "Narrow window" })
map("n", "<Leader>+", function()
  vim.cmd("resize +5")
end, { desc = "Heighten window" })
map("n", "<Leader>-", function()
  vim.cmd("resize -5")
end, { desc = "Shorten window" })

-- Window navigation with Ctrl+h/j/k/l (replaces vim-tmux-navigator;
-- plain window moves only, no tmux integration by request)
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })
