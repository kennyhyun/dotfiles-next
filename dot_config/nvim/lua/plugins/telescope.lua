-- Fuzzy finder: telescope. Replaces fzf.vim / unite / ctrlp from old config.
return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  dependencies = { "nvim-lua/plenary.nvim" },
  keys = {
    -- <C-p> kept from the old config (was :GFiles)
    { "<C-p>", "<cmd>Telescope git_files<cr>", desc = "Find git files" },
    { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
    { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find buffers" },
    { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
    { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
  },
  opts = {
    defaults = {
      -- Use ripgrep-style ignore; respects .gitignore by default.
      file_ignore_patterns = { "node_modules", "%.git/" },
    },
  },
}
