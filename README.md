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
| Linux `linuxdev` role | Docker, kubectl (microk8s is opt-in via `with_microk8s = true`) |
| Linux `lite` role | Low-footprint server: no dev tooling, no build-essential/JRE/perf/kubectl, **podman** instead of docker, **plugin-free Neovim** (built-in syntax only) |

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

### Install settings

Settings live in `~/.config/chezmoi/chezmoi.toml` under `[data]`, one file per
machine (not in this repo). `chezmoi init` asks for the **role** once and writes
the file from `.chezmoi.toml.tmpl`; the other keys default to `false`.

```toml
[data]
  role          = "linuxdev"   # base | linuxdev | lite
  production    = false        # skip developer tooling
  no_sudo       = false        # never call sudo; user-local (Homebrew) only
  with_microk8s = false        # opt-in extras, all additive
  with_kirocrew = false
  with_zfs      = false
  with_clamav   = false
  with_trivy    = false
  with_suricata = false
  with_security = false        # umbrella: clamav + trivy + suricata + osv-scanner
  with_cockpit  = false        # light web admin UI (+ file-sharing) on :9090
  with_samba    = false        # SMB/CIFS server (mixed Win/mac/Linux clients)
  with_nfs      = false        # NFS kernel server (Linux/Unix clients)
  with_nas      = false        # umbrella: cockpit + samba + nfs
```

| Role | Installs |
|------|----------|
| `base` | Essentials, dev tooling, Homebrew CLI set |
| `linuxdev` | `base` + Docker (microk8s is opt-in) |
| `lite` | Low-footprint server: no dev tooling, no build-essential/JRE/perf, kubectl skipped, **podman** instead of docker, **plugin-free Neovim** |

Override a setting for one run with a `DOTFILES_<NAME>` environment variable
(it wins over the file):

```bash
DOTFILES_ROLE=lite chezmoi apply
DOTFILES_WITH_ZFS=1 chezmoi apply        # one-off opt-in
DOTFILES_NO_SUDO=1 chezmoi apply         # no root available
```

The old unprefixed names (`PRODUCTION`, `NO_SUDO`, `WITH_*`) still work but
print a deprecation warning. Do not export them in `~/.zshrc`: names this short
collide with other tools.

**Safety stop.** The package script records `role`, `production` and `no_sudo`
in `~/.local/state/dotfiles/applied` after each successful run. If they differ
on the next run, or nothing is recorded and no role is set, it prints what
changed and stops before installing anything. Accept a deliberate change once
with `DOTFILES_ACCEPT_CHANGE=1 chezmoi apply`. To update files without running
the install scripts at all: `chezmoi apply --exclude=scripts`. Nothing is ever
uninstalled when a setting is turned off.

Extra notes on the opt-ins:

- `with_zfs` installs `zfsutils-linux`, then checks the kernel module can load.
  On Debian with Secure Boot on, the DKMS key must be enrolled once (one
  reboot, console access); the check prints the steps if so. Re-run it any
  time, e.g. before `zpool import`: `"$(chezmoi source-path)/scripts/zfs_check.sh"`
- Security tooling. `osv-scanner` is installed by default with dev tooling (one
  user-local binary, no daemon): it scans lockfiles for known vulnerabilities
  and known malicious packages (OSV + the OpenSSF malicious-packages feed):
  `osv-scanner scan source -r .` Only already-reported packages are caught.
  `with_security = true` turns on everything at once: the three tools below plus
  `osv-scanner` even on `lite` / `production`. Each tool can also be enabled on
  its own (Linux only; needs sudo; idempotent):
  `with_clamav` (on-demand malware scanner: `clamscan -r --infected /mnt/disk1`),
  `with_trivy` (CVE / misconfig / secret scanner: `trivy fs .`), `with_suricata`
  (network IDS; installs + fetches rules but does NOT start monitoring: start it
  with `sudo suricata -i <iface> -D`).
- Preview what a setting would install, without installing:
  `scripts/preview_packages.sh` (add `--all` to compare every role).

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
