# Grok's installer owns the CLI below ~/.grok and links `grok` into
# ~/.local/bin, which startup already puts on PATH. It ships its completion as
# a file instead of a subcommand, so register that file here, after compinit,
# rather than let the installer append a second compinit to the managed
# ~/.zshrc link.
if [[ -r $HOME/.grok/completions/zsh/_grok ]]; then
  fpath+=("$HOME/.grok/completions/zsh")
  autoload -Uz _grok
  compdef _grok grok
fi
