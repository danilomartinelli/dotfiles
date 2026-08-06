autoload -U colors && colors

export LSCOLORS="exfxcxdxbxegedabagacad"
export CLICOLOR=true
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt NO_BG_NICE # don't nice background tasks
setopt NO_HUP
setopt NO_LIST_BEEP
setopt LOCAL_OPTIONS # allow functions to have local options
setopt LOCAL_TRAPS # allow functions to have local traps
setopt HIST_VERIFY
setopt EXTENDED_HISTORY # add timestamps to history
setopt PROMPT_SUBST
setopt IGNORE_EOF

setopt INC_APPEND_HISTORY # write history incrementally
setopt SHARE_HISTORY # share history across sessions, appending incrementally
setopt HIST_IGNORE_ALL_DUPS # don't record dupes in history
setopt HIST_IGNORE_SPACE # skip commands that start with a space
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt EXTENDED_GLOB
setopt INTERACTIVE_COMMENTS

# Report commands that take longer than three seconds.
export REPORTTIME=3
export TIMEFMT=$'\n'"${fg_bold[black]}elapsed: ${fg[white]}%*Es ${fg_bold[black]}(user: ${fg[white]}%*Us ${fg_bold[black]}system: ${fg[white]}%*Ss${fg_bold[black]}) cpu: ${fg[white]}%P ${fg_bold[black]}memory: ${fg[white]}%MK"

# Better history searching with the up/down arrow keys.
zmodload zsh/zle
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
[[ -n ${terminfo[kcuu1]-} ]] && bindkey "$terminfo[kcuu1]" up-line-or-beginning-search
[[ -n ${terminfo[kcud1]-} ]] && bindkey "$terminfo[kcud1]" down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[[5D' beginning-of-line
bindkey '^[[5C' end-of-line
bindkey '^[[3~' delete-char
bindkey '^?' backward-delete-char

# Edit the current command line in $EDITOR (requires a --wait editor).
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Ctrl-W kills one path segment, not the whole path: drop / from word chars.
WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

# Ctrl-S must not freeze the terminal (XOFF flow control).
[[ -t 0 ]] && stty -ixon 2>/dev/null

# fzf pickers use fd (respects .gitignore, includes dotfiles) with bat/eza
# previews. Read at widget time, so order relative to `fzf --zsh` is free.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 60% --layout=reverse --border --info=inline'
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :200 {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"

# Let new Apple Terminal tabs inherit the current working directory.
if [[ $TERM_PROGRAM == Apple_Terminal && -z ${INSIDE_EMACS-} ]]; then
  update_terminal_cwd() {
    local url_path=''
    local i ch hexch LC_CTYPE=C LC_ALL=

    for ((i = 1; i <= ${#PWD}; ++i)); do
      ch=$PWD[i]
      if [[ $ch =~ '[/._~A-Za-z0-9-]' ]]; then
        url_path+=$ch
      else
        printf -v hexch '%02X' "'$ch"
        url_path+="%$hexch"
      fi
    done

    printf '\e]7;%s\a' "file://$HOST$url_path"
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd update_terminal_cwd
fi
