# ~/.config/zsh/chezmoi.zsh — managed by chezmoi.
# This file is NOT a replacement for ~/.zshrc. Your own ~/.zshrc stays intact
# and sources this file at its end:
#
#   [ -r ~/.config/zsh/chezmoi.zsh ] && source ~/.config/zsh/chezmoi.zsh
#
# Put modern, machine-independent zsh tooling here. Anything host-specific
# stays in your own ~/.zshrc (or ~/.zshrc.local).

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

# Ctrl-X Ctrl-E: edit the current command line in $EDITOR (nvim).
# Best way to edit long / multi-line commands comfortably.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
