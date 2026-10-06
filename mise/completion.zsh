#compdef mise
# Generate completions from the installed mise so they never drift from a
# vendored copy. `usage` (required by the generated completion) is installed
# via the Brewfile.
() {
  local checkout=${${(%):-%x}:A:h:h}
  local completion
  [[ ${_dotfiles_mise_ready:-0} == 1 ]] || return 0
  if completion=$("$checkout/_scripts/mise-policy" "$checkout" completion); then
    eval "$completion"
  fi
  return 0
}
