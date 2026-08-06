# Aliases are expanded before completion so `k <tab>`, `d <tab>`, etc.
# complete as their underlying commands without per-alias compdefs.
setopt COMPLETE_IN_WORD
setopt AUTO_LIST
setopt AUTO_MENU
setopt ALWAYS_TO_END

# Match case-insensitively for lowercase input.
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Pasting with tabs does not perform completion.
zstyle ':completion:*' insert-tab pending
zstyle ':completion:*' verbose yes
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' special-dirs true

bindkey '^[[Z' reverse-menu-complete

# Modern CLI integrations. They live in the completion phase because their
# init scripts register compdefs, which are silently dropped before compinit.
# Each hook is guarded so a missing tool never breaks startup.

if (( $+commands[fzf] )); then
  eval "$(fzf --zsh)"
fi

# Atuin owns Ctrl-R (SQLite history with sync); up-arrow keeps the
# prefix search configured in zsh/config.zsh. Must load after fzf so
# the Ctrl-R binding wins. Sync is opt-in: run `atuin register`/`login`.
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
