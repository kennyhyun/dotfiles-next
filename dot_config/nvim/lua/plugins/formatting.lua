-- Formatting: conform.nvim with prettier for web files.
-- Replaces ale's fix-on-save. ESLint fixes are handled by the eslint LSP
-- (see lsp.lua); conform handles prettier formatting.
return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    formatters_by_ft = {
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      jsonc = { "prettier" },
      css = { "prettier" },
      html = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      lua = { "stylua" },
    },
    -- Only format on save if a prettier config / formatter is available;
    -- fall back silently otherwise so non-JS repos aren't disrupted.
    format_on_save = function(bufnr)
      return { timeout_ms = 1000, lsp_format = "fallback" }
    end,
  },
}
