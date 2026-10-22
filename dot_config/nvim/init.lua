-- Neovim configuration entrypoint
-- Minimal, TypeScript-focused setup using lazy.nvim.
-- Plugin specs live in lua/plugins/*.lua and are auto-imported below.

-- Leader must be set before plugins load so mappings register correctly.
vim.g.mapleader = ","
vim.g.maplocalleader = ","

require("config.options")
require("config.keymaps")

-- Plugin-free "minimal" profile (lite server role).
-- The package bootstrap drops ~/.config/nvim/.minimal on the lite role. When
-- present we skip lazy.nvim and all plugins entirely: no third-party code is
-- cloned or compiled, which keeps a small/sensitive server lean and removes the
-- plugin supply-chain surface. Neovim's built-in syntax highlighting and
-- filetype detection still work, which is all a server editor needs.
local minimal = (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("config") .. "/.minimal")
if minimal then
  vim.cmd("syntax on")
  vim.cmd("filetype plugin indent on")
  return
end

-- Bootstrap lazy.nvim (plugin manager). It pins every plugin to a commit via
-- lazy-lock.json, which we commit to the repo for reproducible, supply-chain
-- friendly installs.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    lazyrepo,
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  install = { colorscheme = { "catppuccin" } },
  checker = { enabled = false },
  change_detection = { notify = false },
})
