#!/usr/bin/env bash
# preview_packages.sh — show which packages a *clean* machine would install for
# a given role / option combination, WITHOUT installing anything.
#
# It mirrors the branching logic of
#   .chezmoiscripts/run_once_before_10-install-packages.sh.tmpl
#   .chezmoiscripts/run_once_after_20-setup.sh.tmpl
# and prints the final expected package set per source (apt / brew / npm /
# containers / tailscale / neovim).
#
# Usage:
#   scripts/preview_packages.sh                      # base role (defaults)
#   DOTFILES_ROLE=lite     scripts/preview_packages.sh
#   DOTFILES_ROLE=linuxdev scripts/preview_packages.sh
#   PRODUCTION=1           scripts/preview_packages.sh
#   NO_SUDO=1              scripts/preview_packages.sh
#   scripts/preview_packages.sh --all                # compare every role
#   scripts/preview_packages.sh --check              # verify it matches source
#
# Env flags are read exactly as the install script reads them, so the same
# invocation you would use for `chezmoi apply` previews the right result.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve role / flags the same way the install script does.
# ---------------------------------------------------------------------------
resolve_flags() {
  ROLE="${DOTFILES_ROLE:-base}"
  SKIP_DEVTOOLS=""
  [ -n "${PRODUCTION:-}" ] && SKIP_DEVTOOLS=1
  LITE=""
  [ "$ROLE" = "lite" ] && { LITE=1; SKIP_DEVTOOLS=1; }
  # NO_SUDO: apt + system steps are skipped entirely.
  NO_SUDO_FLAG="${NO_SUDO:-}"
}

# ---------------------------------------------------------------------------
# Package definitions — kept in sync with the install script. The --check mode
# below greps the install script to catch drift.
# ---------------------------------------------------------------------------
APT_BASE="apt-transport-https ca-certificates git git-lfs htop jq curl net-tools psmisc"
APT_HEAVY="build-essential PERF_PKG python3-pip python3-venv pipx default-jre xclip lshw"

BREW_CORE="neovim tmux zsh zsh-autosuggestions zsh-syntax-highlighting ripgrep fd jq git-lfs httpie fzf"
BREW_KUBECTL="kubernetes-cli"
BREW_DEVEXTRAS="fnm awscli deno opentofu graphviz"

# perf package depends on distro; show both possibilities in the preview.
PERF_NOTE="linux-tools-common (ubuntu) | linux-perf (other)"

# ---------------------------------------------------------------------------
# Compute the expected lists for the current flags.
# ---------------------------------------------------------------------------
compute() {
  resolve_flags

  # ---- apt ----
  if [ -n "$NO_SUDO_FLAG" ]; then
    APT_OUT="(none — NO_SUDO: apt skipped entirely)"
  else
    local apt="$APT_BASE"
    [ -z "$LITE" ] && apt="$apt $APT_HEAVY"
    # substitute the perf placeholder with a readable note
    apt="${apt/PERF_PKG/[$PERF_NOTE]}"
    APT_OUT="$apt"
  fi

  # ---- brew ----
  local brew="$BREW_CORE"
  [ -z "$LITE" ] && brew="$brew $BREW_KUBECTL"
  [ -z "$SKIP_DEVTOOLS" ] && brew="$brew $BREW_DEVEXTRAS"
  BREW_OUT="$brew"

  # ---- containers / role extras ----
  if [ -n "$LITE" ]; then
    CONTAINER_OUT="podman (apt)"
  elif [ "$ROLE" = "linuxdev" ] && [ -z "$SKIP_DEVTOOLS" ]; then
    if [ -n "$NO_SUDO_FLAG" ]; then
      CONTAINER_OUT="(none — linuxdev needs sudo; docker/microk8s skipped)"
    else
      CONTAINER_OUT="docker + microk8s (via install_docker.sh / install_microk8s.sh)"
    fi
  else
    CONTAINER_OUT="(none)"
  fi

  # ---- tailscale ----
  if [ -n "$NO_SUDO_FLAG" ]; then
    TAILSCALE_OUT="(skipped on Linux without sudo; run scripts/install_tailscale.sh later)"
  else
    TAILSCALE_OUT="tailscale (always; official installer + systemd service)"
  fi

  # ---- npm globals (after-setup) ----
  if [ -n "$SKIP_DEVTOOLS" ]; then
    NODE_OUT="(none — Node is dev tooling; PRODUCTION/lite skip it)"
  else
    NODE_OUT="Node LTS (fnm) + global: yarn, prettier"
  fi

  # ---- neovim profile ----
  if [ -n "$LITE" ]; then
    NVIM_OUT="plugin-free (marker ~/.config/nvim/.minimal; built-in syntax only)"
  else
    NVIM_OUT="full plugin set (lazy.nvim: lsp/mason, treesitter, telescope, blink.cmp, conform, gitsigns, lualine, catppuccin)"
  fi
}

print_report() {
  compute
  printf '\n\033[1m=== Package preview — clean machine ===\033[0m\n'
  printf '  ROLE=%s  PRODUCTION=%s  NO_SUDO=%s\n' \
    "$ROLE" "${PRODUCTION:-}" "${NO_SUDO_FLAG:-}"
  printf '  (SKIP_DEVTOOLS=%s  LITE=%s)\n\n' "${SKIP_DEVTOOLS:-0}" "${LITE:-0}"

  printf '\033[1;34mapt (system, needs sudo):\033[0m\n'
  printf '  %s\n\n' "$APT_OUT"
  printf '\033[1;34mbrew (user-local):\033[0m\n'
  printf '  %s\n\n' "$BREW_OUT"
  printf '\033[1;34mcontainers / role extras:\033[0m\n'
  printf '  %s\n\n' "$CONTAINER_OUT"
  printf '\033[1;34mtailscale:\033[0m\n'
  printf '  %s\n\n' "$TAILSCALE_OUT"
  printf '\033[1;34mnode / npm (after-setup):\033[0m\n'
  printf '  %s\n\n' "$NODE_OUT"
  printf '\033[1;34mneovim profile:\033[0m\n'
  printf '  %s\n' "$NVIM_OUT"
}

print_all() {
  for combo in \
    "base:" \
    "lite:DOTFILES_ROLE=lite" \
    "linuxdev:DOTFILES_ROLE=linuxdev" \
    "production:PRODUCTION=1" \
    "no-sudo:NO_SUDO=1"; do
    local label="${combo%%:*}" env="${combo#*:}"
    printf '\n\033[1;33m########## %s  (%s) ##########\033[0m\n' "$label" "${env:-defaults}"
    ( unset DOTFILES_ROLE PRODUCTION NO_SUDO
      [ -n "$env" ] && export "${env?}"
      print_report )
  done
}

# ---------------------------------------------------------------------------
# --check: verify our hard-coded lists still match the install script, so this
# preview cannot silently drift from reality.
# ---------------------------------------------------------------------------
check_sync() {
  local src
  src="$(dirname "$0")/../.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
  [ -f "$src" ] || { echo "check: install script not found at $src"; return 2; }
  local fail=0
  for p in $APT_BASE $APT_HEAVY $BREW_CORE $BREW_KUBECTL $BREW_DEVEXTRAS; do
    [ "$p" = "PERF_PKG" ] && continue
    if ! grep -qF "$p" "$src"; then
      echo "DRIFT: '$p' is in preview but not found in install script"; fail=1
    fi
  done
  if [ "$fail" = 0 ]; then
    echo "check: OK — all preview packages are present in the install script."
  else
    echo "check: DRIFT detected — update scripts/preview_packages.sh to match."
    return 1
  fi
}

case "${1:-}" in
  --all)   print_all ;;
  --check) check_sync ;;
  -h|--help)
    sed -n '2,20p' "$0" ;;
  *)       print_report ;;
esac
