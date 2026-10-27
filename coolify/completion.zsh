# Coolify CLI completion from the installed CLI.
if (( $+commands[coolify] )); then
  source <(coolify completion zsh)
fi
