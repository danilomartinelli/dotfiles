# A CLI that generates its own completion never drifts from the installed
# version, but generating it starts the CLI, a tenth of a second for some, in
# every shell. The result is cached instead, and regenerated when the command
# resolves to another file or that file changes, which is what an upgrade does.
#
# Prints nothing and leaves the cache path in REPLY for the caller to source.
# The caller sources it, not this function: a generated script declares its
# state at the top level, and inside a function that state would be local.
# Returns non-zero when there is nothing to source.
#
# Usage: _dotfiles_generated_completion <command> [argument...] && source "$REPLY"
_dotfiles_generated_completion() {
  emulate -L zsh
  local binary cache key line=''
  local -a modified

  (( $+commands[$1] )) || return 1
  binary=${commands[$1]:A}
  zstat -A modified +mtime -- $binary 2>/dev/null || return 1
  key="# $binary $modified[1]"
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/$1-completion.zsh

  [[ -r $cache ]] && IFS= read -r line <$cache
  if [[ $line != $key ]]; then
    mkdir -p -- ${cache:h} 2>/dev/null || return 1
    # Written beside the cache and moved into place, so a shell starting
    # meanwhile never sources half a script.
    if { print -r -- $key; "$@" } >|$cache.$$ 2>/dev/null; then
      mv -f -- $cache.$$ $cache || return 1
    else
      rm -f -- $cache.$$
      return 1
    fi
  fi

  REPLY=$cache
}

zmodload -F zsh/stat b:zstat
