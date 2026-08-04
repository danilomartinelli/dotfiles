# Kubectl completion from the installed CLI.
if (( $+commands[kubectl] )); then
  source <(kubectl completion zsh)
fi
