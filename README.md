# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/), for Linux
and macOS. Bootstraps a fresh machine with a minimal, modern toolchain.

## Highlights

- **Declarative management** via chezmoi (no manual symlinking).
- **Neovim** (Lua + lazy.nvim) replacing the legacy Vim setup — ~9 plugins
  instead of ~40, TypeScript-focused, all plugin commits pinned in
  `lazy-lock.json` for reproducible, supply-chain-conscious installs.
- **zsh / tmux / git / alacritty** configs carried over and cleaned up.
- **Security-hardened bootstrap**: ed25519 SSH keys (separate bastion key),
  no insecure RSA-2048, official `nvm-sh` installer.

## What's included

| Area | Tooling |
|------|---------|
| Editor | Neovim 0.10+ with LSP (`ts_ls`, `eslint`), treesitter, blink.cmp, telescope, conform (prettier), lualine, gitsigns, catppuccin theme |
| Shell | zsh (self-contained, no oh-my-zsh dependency), tmux + tpm |
| Terminal | Alacritty |
| CLI | git, git-lfs, ripgrep, fd, jq, httpie, fzf, tailscale |
| Dev (non-production) | awscli, deno, opentofu, graphviz, Node.js (via fnm) |
| Linux `linuxdev` role | Docker, microk8s, kubectl |

## Neovim

Entry point `~/.config/nvim/init.lua`; plugin specs live in
`~/.config/nvim/lua/plugins/`. Leader key is `,`.

Key maps:

| Key | Action |
|-----|--------|
| `<C-p>` | Find git files (telescope) |
| `<leader>ff` / `fg` / `fb` | Find files / live grep / buffers |
| `gd` / `gr` / `K` | LSP: definition / references / hover |
| `<leader>rn` / `<leader>ca` | LSP: rename / code action |
| `[d` / `]d` | Prev / next diagnostic |
| `]c` / `[c` | Next / prev git hunk (gitsigns) |
| `<leader>hp` / `hb` | Preview hunk / blame line |

LSP servers and formatters are installed automatically via `mason.nvim` on
first launch; treesitter parsers compile on first launch (requires a C
compiler — see Requirements).

## Requirements

- **git**, **curl**
- A **C compiler + headers** for treesitter parser compilation. The bootstrap
  installs this automatically:
  - Linux: `build-essential` (apt)
  - macOS: Xcode Command Line Tools
- `sudo` access (Linux) for system package installation.

## Install

```bash
# 1. Install chezmoi (if not present)
sh -c "$(curl -fsLS get.chezmoi.io)"

# 2. Initialize from this repo and apply
chezmoi init --apply https://github.com/kennyhyun/dotfiles.git
```

chezmoi clones the repo into `~/.local/share/chezmoi`, then on `apply`:

1. `run_once_before_10-install-packages.sh` — system packages, Homebrew, build
   tools.
2. Writes all config files to your home directory.
3. `run_once_after_20-setup.sh` — nvm + Node LTS, tpm, ed25519 SSH keys, git
   identity, Neovim plugin sync, default shell → zsh.

Log out and back in afterwards to pick up the shell and environment.

### Install modes

```bash
# Production server: skip developer tooling
PRODUCTION=1 chezmoi apply

# Linux dev role: also install Docker + microk8s
DOTFILES_ROLE=linuxdev chezmoi apply

# No root available: install everything user-local via Homebrew,
# skip apt packages / chsh
NO_SUDO=1 chezmoi apply
```

The bootstrap is Homebrew-first, so most tooling installs into your home
without root. On a **read-only rootfs** (e.g. a linuxdev WSL image) where the
`rootfs-rw` / `rootfs-ro` helpers exist, the package script unlocks the rootfs
before `sudo` installs and re-locks it afterwards — guaranteed even if the
install fails.

## Day-to-day with chezmoi

```bash
chezmoi edit ~/.zshrc     # edit the source of a managed file
chezmoi diff              # preview pending changes
chezmoi apply             # apply changes to home
chezmoi update            # pull latest from the repo and apply
chezmoi cd                # jump into the source directory
```

## Migration notes (from the legacy Vim dotfiles)

- Vim (dein.vim, ~40 plugins incl. deprecated neocomplete/deoplete/unite,
  tsuquyomi, ale/flow) → Neovim with native LSP and treesitter.
- Removed install-time `npm install` / `./install` build steps (supply-chain
  risk).
- SSH: RSA-2048 → ed25519, with a distinct bastion key (previously the bastion
  key was a copy of the primary key).
- tmux: fixed `${pane_current_path}` → `#{pane_current_path}`; dropped
  vim-tmux-navigator in favor of plain pane navigation.
- zsh: removed oh-my-zsh dependency; PATH de-duplicated via `typeset -U`.
- git config is now `~/.gitconfig` directly (was an `include.path` shim).

## Supported platforms

- ✅ Linux (Debian/Ubuntu, x64/arm64)
- ✅ macOS (Intel & Apple Silicon)
- ✅ WSL2
