# Do not expand aliases before completion has finished (for example,
# `git comm-<tab>`).
setopt COMPLETE_ALIASES
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
