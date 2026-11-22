# Kubectl completion from the installed CLI, cached between shells.
if _dotfiles_generated_completion kubectl completion zsh; then
  source "$REPLY"
fi
