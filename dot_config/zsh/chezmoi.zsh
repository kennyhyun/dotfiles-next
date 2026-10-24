# ~/.config/zsh/chezmoi.zsh — managed by chezmoi.
# This is the shared, machine-independent zsh config. It is NOT ~/.zshrc.
#
# The post-apply setup ensures your ~/.zshrc exists (creating an empty one if
# needed) and that its FIRST line sources this file:
#
#   [ -r ~/.config/zsh/chezmoi.zsh ] && source ~/.config/zsh/chezmoi.zsh
#
# So ~/.zshrc itself plays the role of the old ~/.zshrc.local: put anything
# host-specific (custom functions, extra env, machine paths) directly in your
# ~/.zshrc, below that first source line. chezmoi never overwrites ~/.zshrc.

# ---- Editor ----
export VISUAL=nvim
export EDITOR="$VISUAL"
alias vi=nvim
alias vim=nvim

# ---- Node via fnm (Fast Node Manager) ----
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# ---- fzf (fuzzy finder + Ctrl-R history search) ----
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh) 2>/dev/null || true
fi

# ---- Key bindings: emacs mode for the zsh line editor ----
# Scope is ONLY zsh's line editor (ZLE) — git ($EDITOR=nvim), less and tmux
# have their own keymaps and are unaffected. This keeps ^A/^E/^R/^K etc. working
# as expected regardless of $EDITOR or $VISUAL being set to nvim above.
bindkey -e

# Ctrl-X Ctrl-E: edit the current command line in $EDITOR (nvim).
# Best way to edit long / multi-line commands comfortably.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# ---- ZFS: check the kernel module can load before `zpool import` ----
# On Debian the ZFS module is built by DKMS; with Secure Boot on it will not
# load until the DKMS key is enrolled. Before `zpool import` (also via
# `sudo zpool import`) run scripts/zfs_check.sh: silent when ZFS is ready, else
# it prints the enrolment steps and the import is NOT run.
# Only for interactive zsh (functions, so `sudo` is covered too; a PATH wrapper
# would be bypassed by sudo's secure_path). Defined only where zpool exists.
# Override the checker path with ZFS_CHECK=/path/to/zfs_check.sh.
if command -v zpool >/dev/null 2>&1; then
  _zfs_guard() {
    local chk="${ZFS_CHECK:-$HOME/.local/share/chezmoi/scripts/zfs_check.sh}"
    [ -x "$chk" ] || return 0
    local out rc
    out="$("$chk" 2>&1)"; rc=$?
    # Quiet only when ready AND loaded; otherwise show what the check said.
    if [ $rc -ne 0 ] || [ ! -d /sys/module/zfs ]; then print -r -- "$out"; fi
    return $rc
  }
  zpool() {
    if [[ "$1" == import ]]; then _zfs_guard || return 1; fi
    command zpool "$@"
  }
  sudo() {
    if [[ "$1" == zpool && "$2" == import ]]; then _zfs_guard || return 1; fi
    command sudo "$@"
  }
fi
