#compdef codex
# Codex generates its own completion, so it never drifts from the installed
# version, but generating it costs a tenth of a second per shell. The result is
# cached and regenerated when the Mise lock, which records the Codex version,
# is newer than the cache.
if (( $+commands[codex] )); then
  _dotfiles_codex_completion="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/codex-completion.zsh"
  if [[ ! -s $_dotfiles_codex_completion \
    || $DOTFILES_ROOT/mise/mise.lock -nt $_dotfiles_codex_completion ]]; then
    mkdir -p "${_dotfiles_codex_completion:h}" 2>/dev/null \
      && codex completion zsh >| "$_dotfiles_codex_completion" 2>/dev/null
  fi
  [[ -s $_dotfiles_codex_completion ]] && source "$_dotfiles_codex_completion"
fi
