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
