-- LSP: TypeScript (ts_ls) + ESLint via mason-managed servers.
-- mason installs the language servers into nvim's data dir, so no global
-- npm installs are required.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      -- Diagnostics UI
      vim.diagnostic.config({
        virtual_text = true,
        severity_sort = true,
        float = { border = "rounded" },
      })

      -- Buffer-local LSP keymaps, attached only where a server is active.
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local map = function(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
          end
          map("gd", vim.lsp.buf.definition, "Goto definition")
          map("gr", vim.lsp.buf.references, "References")
          map("gi", vim.lsp.buf.implementation, "Goto implementation")
          map("K", vim.lsp.buf.hover, "Hover docs")
          map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "Prev diagnostic")
          map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic")
        end,
      })

      -- blink.cmp augments the default LSP client capabilities.
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      require("mason-lspconfig").setup({
        ensure_installed = { "ts_ls", "eslint" },
        handlers = {
          function(server_name)
            vim.lsp.config(server_name, { capabilities = capabilities })
            vim.lsp.enable(server_name)
          end,
        },
      })
    end,
  },
}
