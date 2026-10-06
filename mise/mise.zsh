() {
  local checkout=${${(%):-%x}:A:h:h}
  local activation
  typeset -g _dotfiles_mise_ready=0
  (( $+commands[mise] )) || return 0

  if activation=$("$checkout/_scripts/mise-policy" "$checkout" shell); then
    eval "$activation" && _dotfiles_mise_ready=1
  fi
  return 0
}
