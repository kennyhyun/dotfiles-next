-- Completion: blink.cmp (fast, Rust-based). Replaces deoplete/neocomplete.
return {
  "saghen/blink.cmp",
  event = "InsertEnter",
  version = "*", -- use release tags; downloads prebuilt fuzzy matcher binary
  opts = {
    keymap = { preset = "default" }, -- <C-y> accept, <C-n>/<C-p> navigate
    appearance = { nerd_font_variant = "mono" },
    completion = {
      documentation = { auto_show = true, auto_show_delay_ms = 200 },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
    },
    fuzzy = { implementation = "prefer_rust_with_warning" },
  },
  opts_extend = { "sources.default" },
}
