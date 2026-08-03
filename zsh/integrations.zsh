# Modern CLI integrations. Each hook is guarded so a missing tool never
# breaks startup.

if (( $+commands[fzf] )); then
  eval "$(fzf --zsh)"
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
