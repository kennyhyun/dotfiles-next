-- Editor options, migrated from the legacy .vimrc where still useful.
local opt = vim.opt

-- UI
opt.number = true
opt.cursorline = true
opt.signcolumn = "yes" -- keep gutter stable (gitsigns/diagnostics)
opt.termguicolors = true
opt.scrolloff = 4

-- Indentation (2 spaces, matched the old config)
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- System clipboard (works for both macOS and Linux via unnamedplus)
opt.clipboard = "unnamedplus"

-- Allow cursor to wrap across lines with these motions (from old config)
opt.whichwrap:append("<,>,[,],h,l")

-- Encoding
opt.fileencoding = "utf-8"

-- Spell checking for prose/commits (matched old behavior)
opt.spelllang = { "en_us", "cjk" }
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.spell = true
  end,
})

-- Keep undo history across sessions
opt.undofile = true

-- Faster update time improves gitsigns/diagnostics responsiveness
opt.updatetime = 250

-- Use English messages/menus (from old config)
vim.env.LANG = "en_US.UTF-8"
