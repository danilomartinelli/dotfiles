# Uses the Git completion installed by Homebrew.
completion="$HOMEBREW_PREFIX/share/zsh/site-functions/_git"

if [[ -r $completion ]]
then
  autoload -Uz _git
  compdef _git git gitk
fi

unset completion
