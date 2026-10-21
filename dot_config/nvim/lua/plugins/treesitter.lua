-- Treesitter: syntax highlighting & indentation.
-- Replaces the dozens of per-language syntax plugins from the old config.
-- Pinned to the stable `master` branch API (the `main` rewrite is still
-- pre-release and changes its API); lazy-lock.json pins the exact commit.
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  main = "nvim-treesitter.configs",
  opts = {
    ensure_installed = {
      "typescript",
      "tsx",
      "javascript",
      "json",
      "jsonc",
      "html",
      "css",
      "lua",
      "vim",
      "vimdoc",
      "bash",
      "markdown",
      "markdown_inline",
      "yaml",
      "toml",
      "dockerfile",
      "gitcommit",
      "diff",
    },
    highlight = { enable = true },
    indent = { enable = true },
    auto_install = false, -- keep installs explicit/reproducible
  },
}
