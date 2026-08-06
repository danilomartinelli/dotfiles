# Docker CLI completion (same pattern as kubectl/completion.zsh).
if (( $+commands[docker] )); then
  source <(docker completion zsh)
fi
