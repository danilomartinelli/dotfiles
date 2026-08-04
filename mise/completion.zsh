#compdef mise
# Generate completions from the installed mise so they never drift from a
# vendored copy. `usage` (required by the generated completion) is installed
# via the Brewfile.
if (( $+commands[mise] )); then
  source <(mise completion zsh)
fi
